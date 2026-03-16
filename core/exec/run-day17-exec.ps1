param(
  [ValidateSet("seed","close","all")]
  [string]$mode = "all",

  [string]$base = "http://127.0.0.1:8083",
  [string]$internalKey = "goosage-dev",

  [long[]]$userIds = @(5, 9, 10, 12),

  # userId=최근3일 이벤트 총량
  [string]$recent3dMap = "5=1,9=3,10=7,12=12",

  [switch]$ResetHistory = $false,

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
  $tmp = Join-Path $env:TEMP ("req.day17.{0}.{1}.json" -f $PID,(Get-Random))
  Write-Utf8NoBom $tmp $jsonBody
  $h=@()
  foreach($k in $headers.Keys){ $h += @("-H","${k}: $($headers[$k])") }
  $out = & curl.exe -sS -X POST $h -H "Content-Type: application/json" --data-binary "@$tmp" $url
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  return $out
}

function Wait-Server(){
  Info "WAIT server: $base/internal/ping"
  for($i=1;$i -le 60;$i++){
    try{
      $pong = Curl-Text "$base/internal/ping" @{ "X-INTERNAL-KEY" = $internalKey }
      if($pong -eq "pong"){ Ok "ping=pong"; return }
    } catch {}
    Start-Sleep -Seconds 1
  }
  Fail "server not ready"
}

function Parse-Map([string]$text){
  $m=@{}
  foreach($pair in ($text -split ",")){
    $p=$pair.Trim()
    if(-not $p){ continue }
    $kv=$p -split "=",2
    if($kv.Count -ne 2){ continue }
    $m[[long]$kv[0].Trim()] = [int]$kv[1].Trim()
  }
  return $m
}

function Db([string]$sql){
  $tmp = Join-Path $env:TEMP ("goosage_sql_{0}_{1}.sql" -f $PID, (Get-Random))
  Write-Utf8NoBom $tmp $sql

  Get-Content $tmp -Raw | & docker exec -i $mysqlContainer mysql "-u$dbUser" "-p$dbPass" $dbName
  $exitCode = $LASTEXITCODE

  Remove-Item $tmp -Force -ErrorAction SilentlyContinue

  if($exitCode -ne 0){
    throw "Db failed (exitCode=$exitCode)"
  }
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

function Reset-History([long]$uid){
  Info "RESET history (userId=$uid)"
  $sql=@"
DELETE FROM study_events WHERE user_id=$uid;
DELETE FROM daily_learning WHERE user_id=$uid;

SELECT COUNT(*) AS total_events
FROM study_events
WHERE user_id=$uid;
"@
  Db $sql | Out-Host
  Ok "history reset done (userId=$uid)"
}

function Post-Event([long]$uid,[string]$type){
  $json = ([ordered]@{ userId=$uid; type=$type } | ConvertTo-Json -Compress)
  $null = Curl-PostJson "$base/internal/study/events" $json @{ "X-INTERNAL-KEY" = $internalKey }
}

function Shift-NewEventsToOffset([long]$uid,[long]$beforeMaxId,[int]$daysAgo){
  if($daysAgo -le 0){ return }

  Info "SHIFT newly inserted rows => $daysAgo day(s) ago (userId=$uid, id>$beforeMaxId)"

  $sql=@"
UPDATE study_events
SET created_at = DATE_SUB(created_at, INTERVAL $daysAgo DAY)
WHERE user_id = $uid
  AND id > $beforeMaxId;
"@
  Db $sql | Out-Null
  Ok "shift done (userId=$uid, daysAgo=$daysAgo)"
}

function Seed-DayBucket([long]$uid,[int]$daysAgo,[int]$cnt){
  if($cnt -le 0){ return }

  Warn "SEED userId=$uid dayOffset=$daysAgo cnt=$cnt"

  $beforeMaxId = Get-MaxEventId $uid

  1..$cnt | ForEach-Object {
    if($_ % 2 -eq 0){ Post-Event $uid "QUIZ_SUBMIT" }
    else { Post-Event $uid "JUST_OPEN" }
  }

  Shift-NewEventsToOffset $uid $beforeMaxId $daysAgo

  $checkSql=@"
SELECT user_id, DATE(created_at) AS dt, COUNT(*) AS cnt
FROM study_events
WHERE user_id=$uid
GROUP BY user_id, DATE(created_at)
ORDER BY dt;
"@
  Db $checkSql | Out-Host
}

function Seed-Recent3d([long]$uid,[int]$count){
  Warn "---- USER $uid recent3dTarget=$count ----"

  if($ResetHistory -or $mode -eq "all" -or $mode -eq "seed"){
    Reset-History $uid
  }

  if($count -le 0){
    Warn "recent3dTarget=0 => no new evidence injected"
    return
  }

  $today = [Math]::Floor($count / 3)
  $d1    = [Math]::Floor(($count - $today) / 2)
  $d2    = $count - $today - $d1

  $days = @(
    @{ offset = 0; cnt = [int]$today },
    @{ offset = 1; cnt = [int]$d1 },
    @{ offset = 2; cnt = [int]$d2 }
  )

  foreach($d in $days){
    Seed-DayBucket $uid ([int]$d.offset) ([int]$d.cnt)
  }
}

function Rebuild-DailyLearning([long]$uid){
  Info "REBUILD daily_learning (userId=$uid)"

  $sql=@"
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

function Get-Coach([long]$uid){
  Curl-Text "$base/internal/study/coach?userId=$uid" @{ "X-INTERNAL-KEY" = $internalKey }
}

function Save-Coach([long]$uid,[string]$tag,[string]$json){
  $ts=(Get-Date).ToString("yyyyMMdd-HHmmss")
  $dir=Join-Path $PSScriptRoot "artifacts"
  if(-not (Test-Path $dir)){ New-Item -ItemType Directory -Path $dir | Out-Null }
  $file=Join-Path $dir ("coach.day17.{0}.user{1}.{2}.json" -f $tag,$uid,$ts)
  Write-Utf8NoBom $file $json
  Ok "saved => $file"
}

function Print-Db([long]$uid){
  $sql=@"
SELECT DATE(created_at) AS dt, event_type, COUNT(*) AS cnt
FROM study_events
WHERE user_id=$uid
GROUP BY DATE(created_at), event_type
ORDER BY dt DESC, event_type;

SELECT *
FROM daily_learning
WHERE user_id=$uid
ORDER BY ymd DESC;
"@
  Db $sql | Out-Host
}

Wait-Server
Warn "mode=$mode ResetHistory=$ResetHistory"
Warn "recent3dMap=$recent3dMap"

$map = Parse-Map $recent3dMap

if($mode -eq "seed" -or $mode -eq "all"){
  foreach($uid in $userIds){
    $target=0
    if($map.ContainsKey($uid)){ $target=$map[$uid] }
    Seed-Recent3d $uid $target
  }
}

if($mode -eq "close" -or $mode -eq "all"){
  foreach($uid in $userIds){
    Rebuild-DailyLearning $uid
    $coach = Get-Coach $uid
    $coach | Out-Host
    Save-Coach $uid "close" $coach
    Print-Db $uid
  }
}

Ok "DAY17 DONE"