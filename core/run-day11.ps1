# C:\dev\loosegoose\goosage-scripts\run-day11.ps1
param(
  [string]$base = "http://127.0.0.1:8084",
  [string]$internalKey = "goosage-dev",

  # 기본은 u16(=userId 5)로 진행. 필요하면 바꿔.
  [long]$userId = 5,

  # 오늘 데이터 리셋(권장: 테스트/검증용). 실제 누적 모드면 $false로.
  [switch]$ResetToday = $false,

  # Day11 주입 정책(네가 원하는 대로 숫자만 조절)
  [int]$quizCount = 5,
  [int]$wrongCount = 0,   # 0이면 TODAY_DONE 루트(quiz>=5 & wrong==0)
  [int]$justOpenCount = 1,

  # DB 컨테이너/계정 (현재 너 환경 기준)
  [string]$mysqlContainer = "goosage-mysql",
  [string]$dbName = "goosage",
  [string]$dbUser = "root",
  [string]$dbPass = "root123"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ok($msg){ Write-Host "[OK]  $msg" -ForegroundColor Green }
function Info($msg){ Write-Host "[..]  $msg" -ForegroundColor Cyan }
function Warn($msg){ Write-Host "[!!]  $msg" -ForegroundColor Yellow }
function Fail($msg){ Write-Host "[FAIL] $msg" -ForegroundColor Red; throw $msg }

function Write-Utf8NoBom([string]$path, [string]$content) {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

function Curl-Text([string]$url, [hashtable]$headers = @{}) {
  $h = @()
  foreach ($k in $headers.Keys) { $h += @("-H", "${k}: $($headers[$k])") }
  return (& curl.exe -sS $h $url)
}

function Curl-PostJson([string]$url, [string]$jsonBody, [hashtable]$headers = @{}) {
  $tmp = Join-Path $env:TEMP ("req.day11.{0}.{1}.json" -f $PID, (Get-Random))
  Write-Utf8NoBom $tmp $jsonBody

  $h = @()
  foreach ($k in $headers.Keys) { $h += @("-H", "${k}: $($headers[$k])") }

  $out = & curl.exe -sS -X POST $h -H "Content-Type: application/json" --data-binary "@$tmp" $url
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  return $out
}

function Wait-Server() {
  Info "WAIT server: $base/internal/ping"
  for ($i=1; $i -le 60; $i++) {
    try {
      $pong = Curl-Text "$base/internal/ping" @{ "X-INTERNAL-KEY" = $internalKey } @{ "X-INTERNAL-KEY" = $internalKey }
      if ($pong -eq "pong") { Ok "ping=pong"; return }
    } catch {}
    Start-Sleep -Seconds 1
  }
  Fail "server not ready"
}

function Reset-TodayData() {
  Info "RESET today data (userId=$userId)"
  $sql = "DELETE FROM study_events WHERE user_id=$userId AND DATE(created_at)=CURDATE(); " +
         "DELETE FROM daily_learning WHERE user_id=$userId AND ymd=CURDATE(); " +
         "SELECT COUNT(*) AS cnt FROM study_events WHERE user_id=$userId AND DATE(created_at)=CURDATE();"
  $out = & docker exec $mysqlContainer sh -lc "mysql -u$dbUser -p$dbPass $dbName -e '$sql'"
  $out | Out-Host
  Ok "reset done"
}

function Post-Event([string]$type, [Nullable[long]]$knowledgeId = $null) {
  $body = [ordered]@{ userId = $userId; type = $type }
  if ($null -ne $knowledgeId) { $body.knowledgeId = $knowledgeId }
  $json = ($body | ConvertTo-Json -Compress)

  Info "EVENT $type (knowledgeId=$knowledgeId)"
  $res = Curl-PostJson "$base/internal/study/events" $json @{ "X-INTERNAL-KEY" = $internalKey }
  # 응답이 wrapper일 수도, 아닐 수도 있으니 그냥 출력만 최소화
  if (-not $res) { Warn "empty response" } else { Ok "event ok" }
}

function Get-CoachJson() {
  return Curl-Text "$base/internal/study/coach?userId=$userId" @{ "X-INTERNAL-KEY" = $internalKey }
}

function Save-Coach([string]$json) {
  $ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $outDir = Join-Path $PSScriptRoot "artifacts"
  if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
  $outFile = Join-Path $outDir ("coach.day11.user{0}.{1}.json" -f $userId, $ts)
  Write-Utf8NoBom $outFile $json
  Ok "coach saved => $outFile"
}

function Print-DbCounts() {
  Info "DB COUNT (today) userId=$userId"
  & docker exec $mysqlContainer sh -lc "mysql -u$dbUser -p$dbPass $dbName -e 'SELECT type, COUNT(*) cnt FROM study_events WHERE user_id=$userId AND DATE(created_at)=CURDATE() GROUP BY type ORDER BY type;'"
  & docker exec $mysqlContainer sh -lc "mysql -u$dbUser -p$dbPass $dbName -e 'SELECT * FROM daily_learning WHERE user_id=$userId AND ymd=CURDATE();'"
}

# =========================
# MAIN
# =========================
Wait-Server

if ($ResetToday) { Reset-TodayData } else { Warn "ResetToday=OFF (누적 모드)" }

# Day11: JUST_OPEN
1..$justOpenCount | % { Post-Event "JUST_OPEN" $null }

# Day11: REVIEW_WRONG
1..$wrongCount | % { Post-Event "REVIEW_WRONG" 1 }

# Day11: QUIZ_SUBMIT
1..$quizCount | % { Post-Event "QUIZ_SUBMIT" $null }

# Coach 확인 + 저장
$coachJson = Get-CoachJson
$coachJson | Out-Host
Save-Coach $coachJson

# DB 검증(오늘치)
Print-DbCounts

Ok "DAY11 DONE"
