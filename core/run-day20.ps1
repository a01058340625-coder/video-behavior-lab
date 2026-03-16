param(
  [ValidateSet("seed","close","all")]
  [string]$mode = "all",

  [string]$base = "http://127.0.0.1:8083",
  [string]$internalKey = "goosage-dev",

  [long[]]$userIds = @(5, 9, 10, 12),

  # burnout 후보
  [long[]]$burnoutUsers = @(5, 12),

  # 정공법: 기본 true
  [switch]$ResetHistory = $true,

  [string]$mysqlContainer = "goosage-mysql",
  [string]$dbName = "goosage",
  [string]$dbUser = "root",
  [string]$dbPass = "root123"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ok($m){ Write-Host "[OK]  $m" -ForegroundColor Green }
function Info($m){ Write-Host "[..]  $m" -ForegroundColor Cyan }
function Warn($m){ Write-Host "[!!]  $m" -ForegroundColor Yellow }
function Fail($m){ Write-Host "[FAIL] $m" -ForegroundColor Red; throw $m }

function Write-Utf8NoBom([string]$p,[string]$c){
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($p,$c,$enc)
}

function Curl-Text([string]$url,[hashtable]$headers=@{}){
  $h=@()
  foreach($k in $headers.Keys){ $h += @("-H","${k}: $($headers[$k])") }
  & curl.exe -sS $h $url
}

function Curl-PostJson([string]$url,[string]$jsonBody,[hashtable]$headers=@{}){
  $tmp = Join-Path $env:TEMP ("req.day20.{0}.{1}.json" -f $PID,(Get-Random))
  Write-Utf8NoBom $tmp $jsonBody
  $h=@()
  foreach($k in $headers.Keys){ $h += @("-H","${k}: $($headers[$k])") }
  $out = & curl.exe -sS -X POST $h -H "Content-Type: application/json" --data-binary "@$tmp" $url
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  return $out
}

function Wait-Server(){
  Info "WAIT server: $base/internal/ping"
  for($i=1; $i -le 60; $i++){
    try{
      $pong = Curl-Text "$base/internal/ping" @{ "X-INTERNAL-KEY" = $internalKey }
      if($pong -eq "pong"){
        Ok "ping=pong"
        return
      }
    } catch {}
    Start-Sleep -Seconds 1
  }
  Fail "server not ready"
}

function Db([string]$sql){
  $tmp = Join-Path $env:TEMP ("goosage_sql_day20_{0}_{1}.sql" -f $PID,(Get-Random))
  Write-Utf8NoBom $tmp $sql

  Get-Content $tmp -Raw | & docker exec -i $mysqlContainer mysql "-u$dbUser" "-p$dbPass" $dbName
  $exitCode = $LASTEXITCODE

  Remove-Item $tmp -Force -ErrorAction SilentlyContinue

  if($exitCode -ne 0){
    throw "Db failed (exitCode=$exitCode)"
  }
}

function Reset-HistoryFn([long]$uid){
  Info "RESET history (userId=$uid)"
  $sql = @"
DELETE FROM study_events WHERE user_id = $uid;
DELETE FROM daily_learning WHERE user_id = $uid;

SELECT COUNT(*) AS total_events
FROM study_events
WHERE user_id = $uid;
"@
  Db $sql | Out-Host
  Ok "history reset done (userId=$uid)"
}

function Get-MaxEventId([long]$uid){
  $sql = @"
SELECT COALESCE(MAX(id), 0) AS max_id
FROM study_events
WHERE user_id = $uid;
"@
  $out = Db $sql | Out-String
  $lines = @($out -split "`r?`n") | Where-Object { $_.Trim() -ne "" }
  if($lines.Count -lt 2){ return 0L }
  return [long]($lines[-1].Trim())
}

function Post-Event([long]$uid,[string]$type){
  $json = ([ordered]@{ userId=$uid; type=$type } | ConvertTo-Json -Compress)
  $out = Curl-PostJson "$base/internal/study/events" $json @{ "X-INTERNAL-KEY" = $internalKey }
  if(-not $out){
    Fail "event post failed (userId=$uid, type=$type)"
  }
}

function Shift-NewEventsToOffset([long]$uid,[long]$beforeMaxId,[int]$daysAgo){
  if($daysAgo -le 0){ return }

  Info "SHIFT newly inserted rows => $daysAgo day(s) ago (userId=$uid, id>$beforeMaxId)"

  $sql = @"
UPDATE study_events
SET created_at = DATE_SUB(created_at, INTERVAL $daysAgo DAY)
WHERE user_id = $uid
  AND id > $beforeMaxId;
"@
  Db $sql | Out-Null
  Ok "shift done (userId=$uid, daysAgo=$daysAgo)"
}

function Rebuild-DailyLearning([long]$uid){
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
  Db $sql | Out-Null
  Ok "daily_learning rebuild done (userId=$uid)"
}

function Seed-Day([long]$uid,[int]$daysAgo,[int]$jo,[int]$quiz){
  $beforeMaxId = Get-MaxEventId $uid

  if($jo -gt 0){
    1..$jo | ForEach-Object { Post-Event $uid "JUST_OPEN" }
  }

  if($quiz -gt 0){
    1..$quiz | ForEach-Object { Post-Event $uid "QUIZ_SUBMIT" }
  }

  Shift-NewEventsToOffset $uid $beforeMaxId $daysAgo
}

function Seed-Burnout([long]$uid){
  Warn "---- USER $uid BURNOUT ----"

  if($ResetHistory -or $mode -eq "all" -or $mode -eq "seed"){
    Reset-HistoryFn $uid
  }

  # 최근 3일 과몰입, 오늘 0개
  Seed-Day $uid 1 2 8
  Seed-Day $uid 2 2 8
  Seed-Day $uid 3 2 8

  Rebuild-DailyLearning $uid

  $checkSql = @"
SELECT DATE(created_at) AS dt, event_type, COUNT(*) AS cnt
FROM study_events
WHERE user_id = $uid
GROUP BY DATE(created_at), event_type
ORDER BY dt DESC, event_type;

SELECT *
FROM daily_learning
WHERE user_id = $uid
ORDER BY ymd DESC;
"@
  Db $checkSql | Out-Host
}

function Seed-Normal([long]$uid){
  Warn "---- USER $uid NORMAL ----"

  if($ResetHistory -or $mode -eq "all" -or $mode -eq "seed"){
    Reset-HistoryFn $uid
  }

  # 최근 3일 적당히 유지 + 오늘도 유지
  Seed-Day $uid 0 1 3
  Seed-Day $uid 1 1 2
  Seed-Day $uid 2 1 2

  Rebuild-DailyLearning $uid

  $checkSql = @"
SELECT DATE(created_at) AS dt, event_type, COUNT(*) AS cnt
FROM study_events
WHERE user_id = $uid
GROUP BY DATE(created_at), event_type
ORDER BY dt DESC, event_type;

SELECT *
FROM daily_learning
WHERE user_id = $uid
ORDER BY ymd DESC;
"@
  Db $checkSql | Out-Host
}

function Get-Coach([long]$uid){
  Curl-Text "$base/internal/study/coach?userId=$uid" @{ "X-INTERNAL-KEY" = $internalKey }
}

function Save-Coach([long]$uid,[string]$tag,[string]$json){
  $ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $dir = Join-Path $PSScriptRoot "artifacts"
  if(-not (Test-Path $dir)){ New-Item -ItemType Directory -Path $dir | Out-Null }
  $file = Join-Path $dir ("coach.day20.{0}.user{1}.{2}.json" -f $tag,$uid,$ts)
  Write-Utf8NoBom $file $json
  Ok "saved => $file"
}

Wait-Server
Warn "mode=$mode ResetHistory=$ResetHistory"
Warn "burnoutUsers=$($burnoutUsers -join ',')"

if($mode -eq "seed" -or $mode -eq "all"){
  foreach($uid in $userIds){
    if($burnoutUsers -contains $uid){
      Seed-Burnout $uid
    } else {
      Seed-Normal $uid
    }
  }
}

if($mode -eq "close" -or $mode -eq "all"){
  foreach($uid in $userIds){
    $coach = Get-Coach $uid
    $coach | Out-Host
    Save-Coach $uid "close" $coach
  }
}

Ok "DAY20 DONE"