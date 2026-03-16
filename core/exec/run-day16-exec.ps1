param(
  [ValidateSet("seed","close","all")]
  [string]$mode = "all",

  [string]$base = "http://127.0.0.1:8083",
  [string]$internalKey = "goosage-dev",

  # Day16 대상 유저
  [long[]]$userIds = @(5, 9, 10, 12),

  # userId=expectedStreakDays
  # 예: 5번=3일 연속, 9번=1일, 10번=0일, 12번=5일
  [string]$streakMap = "5=3,9=1,10=0,12=5",

  # 하루당 생성할 기본 이벤트 수
  [int]$dailyJustOpen = 1,
  [int]$dailyQuiz = 2,

  # 오늘 데이터 초기화 여부
  [switch]$ResetToday = $false,

  # 과거 데이터까지 싹 지울지 여부
  [switch]$ResetHistory = $false,

  # DB
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
  $tmp = Join-Path $env:TEMP ("req.day16.{0}.{1}.json" -f $PID, (Get-Random))
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

function Parse-StreakMap([string]$text) {
  $m = @{}
  foreach ($pair in ($text -split ",")) {
    $p = $pair.Trim()
    if (-not $p) { continue }
    $kv = $p -split "=", 2
    if ($kv.Count -ne 2) { continue }
    $uid = [long]($kv[0].Trim())
    $days = [int]($kv[1].Trim())
    $m[$uid] = $days
  }
  return $m
}

function Invoke-Db([string]$sql) {
  $tmp = Join-Path $env:TEMP ("goosage_sql_{0}_{1}.sql" -f $PID, (Get-Random))
  Write-Utf8NoBom $tmp $sql

  Get-Content $tmp -Raw | & docker exec -i $mysqlContainer mysql "-u$dbUser" "-p$dbPass" $dbName
  $exitCode = $LASTEXITCODE

  Remove-Item $tmp -Force -ErrorAction SilentlyContinue

  if ($exitCode -ne 0) {
    throw "Invoke-Db failed (exitCode=$exitCode)"
  }
}

function Get-MaxEventId([long]$uid) {
  $sql = @"
SELECT COALESCE(MAX(id), 0) AS max_id
FROM study_events
WHERE user_id = $uid;
"@
  $out = Invoke-Db $sql | Out-String
  $lines = @($out -split "`r?`n") | Where-Object { $_.Trim() -ne "" }
  if ($lines.Count -lt 2) { return 0L }
  return [long]($lines[-1].Trim())
}

function Reset-UserToday([long]$uid) {
  Info "RESET today data (userId=$uid)"
  $sql = @"
DELETE FROM study_events
WHERE user_id = $uid
  AND DATE(created_at)=CURDATE();

DELETE FROM daily_learning
WHERE user_id = $uid
  AND ymd=CURDATE();

SELECT COUNT(*) AS today_events
FROM study_events
WHERE user_id = $uid
  AND DATE(created_at)=CURDATE();
"@
  Invoke-Db $sql | Out-Host
  Ok "today reset done (userId=$uid)"
}

function Reset-UserHistory([long]$uid) {
  Info "RESET history data (userId=$uid)"
  $sql = @"
DELETE FROM study_events WHERE user_id = $uid;
DELETE FROM daily_learning WHERE user_id = $uid;

SELECT COUNT(*) AS total_events
FROM study_events
WHERE user_id = $uid;
"@
  Invoke-Db $sql | Out-Host
  Ok "history reset done (userId=$uid)"
}

function Post-Event([long]$uid, [string]$type) {
  $body = [ordered]@{ userId = $uid; type = $type }
  $json = ($body | ConvertTo-Json -Compress)

  Info "EVENT u$uid $type"
  $res = Curl-PostJson "$base/internal/study/events" $json @{ "X-INTERNAL-KEY" = $internalKey }
  if (-not $res) { Warn "empty response" } else { Ok "event ok" }
}

function Shift-NewEventsToOffset([long]$uid, [long]$beforeMaxId, [int]$daysAgo) {
  if ($daysAgo -le 0) { return }

  Info "SHIFT newly inserted rows => $daysAgo day(s) ago (userId=$uid, id>$beforeMaxId)"

  $sql = @"
UPDATE study_events
SET created_at = DATE_SUB(created_at, INTERVAL $daysAgo DAY)
WHERE user_id = $uid
  AND id > $beforeMaxId;
"@
  Invoke-Db $sql | Out-Null
  Ok "shift done (userId=$uid, daysAgo=$daysAgo)"
}

function Seed-OneDay([long]$uid, [int]$daysAgo) {
  Warn "SEED userId=$uid dayOffset=$daysAgo (1 day evidence)"

  $beforeMaxId = Get-MaxEventId $uid

  1..$dailyJustOpen | ForEach-Object { Post-Event $uid "JUST_OPEN" }
  1..$dailyQuiz     | ForEach-Object { Post-Event $uid "QUIZ_SUBMIT" }

  Shift-NewEventsToOffset $uid $beforeMaxId $daysAgo

  $checkSql = @"
SELECT user_id, DATE(created_at) AS dt, COUNT(*) AS cnt
FROM study_events
WHERE user_id = $uid
GROUP BY user_id, DATE(created_at)
ORDER BY dt;
"@
  Invoke-Db $checkSql | Out-Host
}

function Seed-Streak([long]$uid, [int]$streakDays) {
  Warn "---- USER $uid expectedStreak=$streakDays ----"

  # Day16은 streak 검증일이므로 기본은 깨끗하게 시작
  if ($ResetHistory -or (-not $ResetToday)) {
    Reset-UserHistory $uid
  } elseif ($ResetToday) {
    Reset-UserToday $uid
  }

  if ($streakDays -le 0) {
    Warn "streakDays=0 => no new evidence injected"
    return
  }

  for ($d=0; $d -lt $streakDays; $d++) {
    Seed-OneDay $uid $d
  }
}

function Rebuild-DailyLearning([long]$uid) {
  Info "REBUILD daily_learning (userId=$uid)"

  $sql = @"
DELETE FROM daily_learning WHERE user_id = $uid;

INSERT INTO daily_learning (user_id, ymd, events_count, quiz_submits, wrong_reviews, last_event_at)
SELECT
  user_id,
  DATE(created_at) AS ymd,
  COUNT(*) AS events_count,
  SUM(CASE WHEN event_type = 'QUIZ_SUBMIT' THEN 1 ELSE 0 END) AS quiz_submits,
  SUM(CASE WHEN event_type IN ('REVIEW_WRONG', 'WRONG_REVIEW_DONE') THEN 1 ELSE 0 END) AS wrong_reviews,
  MAX(created_at) AS last_event_at
FROM study_events
WHERE user_id = $uid
GROUP BY user_id, DATE(created_at)
ORDER BY ymd;
"@
  Invoke-Db $sql | Out-Null
  Ok "daily_learning rebuild done (userId=$uid)"
}

function Get-CoachJson([long]$uid) {
  return Curl-Text "$base/internal/study/coach?userId=$uid" @{ "X-INTERNAL-KEY" = $internalKey }
}

function Save-Coach([long]$uid, [string]$tag, [string]$json) {
  $ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $outDir = Join-Path $PSScriptRoot "artifacts"
  if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
  $outFile = Join-Path $outDir ("coach.day16.{0}.user{1}.{2}.json" -f $tag, $uid, $ts)
  Write-Utf8NoBom $outFile $json
  Ok "coach saved => $outFile"
}

function Print-DbCounts([long]$uid) {
  Info "DB COUNT (userId=$uid)"
  $sql = @"
SELECT DATE(created_at) AS dt, event_type, COUNT(*) AS cnt
FROM study_events
WHERE user_id = $uid
GROUP BY DATE(created_at), event_type
ORDER BY dt DESC, event_type;

SELECT *
FROM daily_learning
WHERE user_id = $uid
ORDER BY ymd DESC
LIMIT 10;
"@
  Invoke-Db $sql | Out-Host
}

# =========================
# MAIN
# =========================
Wait-Server
Warn "mode=$mode ResetToday=$ResetToday ResetHistory=$ResetHistory"
Warn "streakMap=$streakMap"

$map = Parse-StreakMap $streakMap

if ($mode -eq "seed" -or $mode -eq "all") {
  foreach ($uid in $userIds) {
    $expected = 0
    if ($map.ContainsKey($uid)) { $expected = [int]$map[$uid] }
    Seed-Streak $uid $expected
  }
}

if ($mode -eq "close" -or $mode -eq "all") {
  foreach ($uid in $userIds) {
    Rebuild-DailyLearning $uid
    $coach = Get-CoachJson $uid
    $coach | Out-Host
    Save-Coach $uid "close" $coach
    Print-DbCounts $uid
  }
}

Ok "DAY16 DONE"