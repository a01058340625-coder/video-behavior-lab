# C:\dev\loosegoose\goosage-scripts\run-day15.ps1
param(
  [ValidateSet("sweep","close")]
  [string]$mode = "sweep",

  [string]$base = "http://127.0.0.1:8083",
  [string]$internalKey = "goosage-dev",

  # Day15는 "민감도 스윕" 대상 유저를 적게 잡는 게 좋다
  [long[]]$userIds = @(5, 9, 10, 12),

  # 오늘 리셋은 기본 OFF (누적 모드)
  [switch]$ResetToday = $false,

  # wrong 이벤트에 사용할 knowledgeId
  [long]$wrongKnowledgeId = 1,

  # 스윕 단계(민감도 조절 입력값)
  # step1: 거의 안전(오답0)
  # step2: 오답 소량
  # step3: 오답 중간
  # step4: 오답 다량
  [ValidateSet("1","2","3","4")]
  [string]$maxStep = "4",

  # 각 step의 기본 주입량 (원하면 여기 숫자만 바꿔서 조절)
  [int]$step1_jo = 1, [int]$step1_quiz = 5, [int]$step1_wrong = 0,
  [int]$step2_jo = 1, [int]$step2_quiz = 5, [int]$step2_wrong = 1,
  [int]$step3_jo = 1, [int]$step3_quiz = 3, [int]$step3_wrong = 3,
  [int]$step4_jo = 1, [int]$step4_quiz = 1, [int]$step4_wrong = 7,

  # DB 컨테이너/계정
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
  $tmp = Join-Path $env:TEMP ("req.day15.{0}.{1}.json" -f $PID, (Get-Random))
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
      $pong = Curl-Text "$base/internal/ping" @{ "X-INTERNAL-KEY" = $internalKey }
      if ($pong -eq "pong") { Ok "ping=pong"; return }
    } catch {}
    Start-Sleep -Seconds 1
  }
  Fail "server not ready"
}

function Reset-TodayData([long]$uid) {
  Info "RESET today data (userId=$uid)"
  $sql = "DELETE FROM study_events WHERE user_id=$uid AND DATE(created_at)=CURDATE(); " +
         "DELETE FROM daily_learning WHERE user_id=$uid AND ymd=CURDATE();"
  & docker exec $mysqlContainer sh -lc "mysql -u$dbUser -p$dbPass $dbName -e '$sql'" | Out-Host
  Ok "reset done (userId=$uid)"
}

function Post-Event([long]$uid, [string]$type, [Nullable[long]]$knowledgeId = $null) {
  $body = [ordered]@{ userId = $uid; type = $type }
  if ($null -ne $knowledgeId) { $body.knowledgeId = $knowledgeId }
  $json = ($body | ConvertTo-Json -Compress)

  Info "EVENT u$uid $type (knowledgeId=$knowledgeId)"
  $res = Curl-PostJson "$base/internal/study/events" $json @{ "X-INTERNAL-KEY" = $internalKey }
  if (-not $res) { Warn "empty response" } else { Ok "event ok" }
}

function Get-CoachJson([long]$uid) {
  return Curl-Text "$base/internal/study/coach?userId=$uid" @{ "X-INTERNAL-KEY" = $internalKey }
}

function Save-Coach([long]$uid, [string]$tag, [string]$json) {
  $ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $outDir = Join-Path $PSScriptRoot "artifacts"
  if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
  $outFile = Join-Path $outDir ("coach.day15.{0}.user{1}.{2}.json" -f $tag, $uid, $ts)
  Write-Utf8NoBom $outFile $json
  Ok "coach saved => $outFile"
}

function Print-DbCounts([long]$uid) {
  Info "DB COUNT (today) userId=$uid"
  & docker exec $mysqlContainer sh -lc "mysql -u$dbUser -p$dbPass $dbName -e 'SELECT type, COUNT(*) cnt FROM study_events WHERE user_id=$uid AND DATE(created_at)=CURDATE() GROUP BY type ORDER BY type;'" | Out-Host
  & docker exec $mysqlContainer sh -lc "mysql -u$dbUser -p$dbPass $dbName -e 'SELECT * FROM daily_learning WHERE user_id=$uid AND ymd=CURDATE();'" | Out-Host
}

function Step-Config([int]$step) {
  switch ($step) {
    1 { return @{ jo=$step1_jo; quiz=$step1_quiz; wrong=$step1_wrong } }
    2 { return @{ jo=$step2_jo; quiz=$step2_quiz; wrong=$step2_wrong } }
    3 { return @{ jo=$step3_jo; quiz=$step3_quiz; wrong=$step3_wrong } }
    default { return @{ jo=$step4_jo; quiz=$step4_quiz; wrong=$step4_wrong } }
  }
}

# =========================
# MAIN
# =========================
Wait-Server
if ($ResetToday) { Warn "ResetToday=ON (오늘치 초기화)" } else { Warn "ResetToday=OFF (누적)" }

$max = [int]$maxStep

if ($mode -eq "close") {
  Warn "MODE=close (coach+db만)"
  foreach ($uid in $userIds) {
    $coach = Get-CoachJson $uid
    $coach | Out-Host
    Save-Coach $uid "close" $coach
    Print-DbCounts $uid
  }
  Ok "DAY15 CLOSE DONE"
  exit 0
}

Warn "MODE=sweep (민감도 입력값 스윕) maxStep=$max"

$summary = @()

foreach ($uid in $userIds) {
  Warn "========================"
  Warn "USER $uid"
  Warn "========================"

  if ($ResetToday) { Reset-TodayData $uid }

  for ($s=1; $s -le $max; $s++) {
    $c = Step-Config $s
    $jo = [int]$c.jo
    $qz = [int]$c.quiz
    $wr = [int]$c.wrong

    Warn "---- STEP $s (jo=$jo quiz=$qz wrong=$wr) ----"

    if ($jo -gt 0) { 1..$jo | ForEach-Object { Post-Event $uid "JUST_OPEN" $null } }
    if ($wr -gt 0) { 1..$wr | ForEach-Object { Post-Event $uid "REVIEW_WRONG" $wrongKnowledgeId } }
    if ($qz -gt 0) { 1..$qz | ForEach-Object { Post-Event $uid "QUIZ_SUBMIT" $null } }

    $coach = Get-CoachJson $uid
    $coach | Out-Host
    Save-Coach $uid ("s{0}" -f $s) $coach
    Print-DbCounts $uid

    # 간단 요약(텍스트 파싱 없이, 나중에 artifacts로 분석)
    $summary += [pscustomobject]@{ userId=$uid; step=$s; jo=$jo; quiz=$qz; wrong=$wr; coachFileTag=("s{0}" -f $s) }
  }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Day15 SWEEP DONE (summary)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$summary | Format-Table -AutoSize

Ok "DAY15 DONE"