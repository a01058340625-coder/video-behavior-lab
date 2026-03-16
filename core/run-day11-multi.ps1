# C:\dev\loosegoose\goosage-scripts\run-day11-multi.ps1
param(
  [string]$base = "http://127.0.0.1:8084",
  [string]$internalKey = "goosage-dev",

  # 기본: u12~u21 (= userId 12..21)
  [long[]]$userIds = (12..21),

  # 누적 적립이면 기본 OFF (같은 날 여러번 돌리면 계속 쌓임)
  [switch]$ResetToday = $false,

  # Day11 패턴(원하면 숫자만 바꿔)
  [int]$justOpenCount = 1,
  [int]$quizCount = 5,
  [int]$wrongCount = 0,      # 0이면 TODAY_DONE 루트(quiz>=5 & wrong==0) 가능

  # DB 컨테이너/계정(현재 너 환경 기준)
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
  $tmp = Join-Path $env:TEMP ("req.day11multi.{0}.{1}.json" -f $PID, (Get-Random))
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
      $pong = Curl-Text "$base/internal/ping"
      if ($pong -eq "pong") { Ok "ping=pong"; return }
    } catch {}
    Start-Sleep -Seconds 1
  }
  Fail "server not ready"
}

function Reset-TodayData([long]$uid) {
  Info "RESET today data (userId=$uid)"
  $sql = "DELETE FROM study_events WHERE user_id=$uid AND DATE(created_at)=CURDATE(); " +
         "DELETE FROM daily_learning WHERE user_id=$uid AND ymd=CURDATE(); " +
         "SELECT COUNT(*) AS cnt FROM study_events WHERE user_id=$uid AND DATE(created_at)=CURDATE();"
  & docker exec $mysqlContainer sh -lc "mysql -u$dbUser -p$dbPass $dbName -e '$sql'" | Out-Host
}

function Post-Event([long]$uid, [string]$type, [Nullable[long]]$knowledgeId = $null) {
  $body = [ordered]@{ userId = $uid; type = $type }
  if ($null -ne $knowledgeId) { $body.knowledgeId = $knowledgeId }
  $json = ($body | ConvertTo-Json -Compress)

  Info "EVENT userId=$uid type=$type (knowledgeId=$knowledgeId)"
  $res = Curl-PostJson "$base/internal/study/events" $json @{ "X-INTERNAL-KEY" = $internalKey }
  if (-not $res) { Warn "empty response (still may be OK)" } else { Ok "event ok" }
}

function Get-CoachJson([long]$uid) {
  return Curl-Text "$base/internal/study/coach?userId=$uid" @{ "X-INTERNAL-KEY" = $internalKey }
}

function Save-Coach([long]$uid, [string]$json) {
  $ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $outDir = Join-Path $PSScriptRoot "artifacts"
  if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
  $outFile = Join-Path $outDir ("coach.day11.user{0}.{1}.json" -f $uid, $ts)
  Write-Utf8NoBom $outFile $json
  Ok "coach saved => $outFile"
}

function Print-DbSummary([long[]]$uids) {
  $in = ($uids | ForEach-Object { "$_" }) -join ","
  Info "DB SUMMARY (today) userIds=[$in]"

  & docker exec $mysqlContainer sh -lc "mysql -u$dbUser -p$dbPass $dbName -e 'SELECT user_id, type, COUNT(*) cnt FROM study_events WHERE user_id IN ($in) AND DATE(created_at)=CURDATE() GROUP BY user_id, type ORDER BY user_id, type;'"
  & docker exec $mysqlContainer sh -lc "mysql -u$dbUser -p$dbPass $dbName -e 'SELECT user_id, ymd, events_count, quiz_submits, wrong_reviews, last_event_at FROM daily_learning WHERE user_id IN ($in) AND ymd=CURDATE() ORDER BY user_id;'"
}

# =========================
# MAIN
# =========================
Wait-Server

Warn "MODE: ResetToday=$ResetToday / justOpen=$justOpenCount / wrong=$wrongCount / quiz=$quizCount"
Warn "NOTE: ResetToday=OFF면 같은 날 여러 번 돌릴수록 events_count가 계속 증가함"

foreach ($uid in $userIds) {
  Write-Host ""
  Write-Host "========== DAY11 MULTI | userId=$uid ==========" -ForegroundColor White

  if ($ResetToday) { Reset-TodayData $uid }

  1..$justOpenCount | % { Post-Event $uid "JUST_OPEN" $null }
  1..$wrongCount    | % { Post-Event $uid "REVIEW_WRONG" 1 }
  1..$quizCount     | % { Post-Event $uid "QUIZ_SUBMIT" $null }

  $coachJson = Get-CoachJson $uid
  $coachJson | Out-Host
  Save-Coach $uid $coachJson
}

Print-DbSummary $userIds
Ok "DAY11 MULTI DONE"