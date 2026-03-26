param(
  [long[]]$userIds = @(31,32,33),

  [string]$base = "http://127.0.0.1:8084",
  [string]$internalKey = "goosage-dev",

  [string]$mysqlContainer = "goosage-mysql",
  [string]$dbName = "goosage",
  [string]$dbUser = "root",
  [string]$dbPass = "root123"
)

chcp 65001 > $null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Utf8NoBom([string]$p,[string]$c){
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($p,$c,$enc)
}

function Curl-Text([string]$url){
  & curl.exe -sS -H "X-INTERNAL-KEY: $internalKey" $url
}

function Curl-PostJson([string]$url,[string]$json){
  $tmp = Join-Path $env:TEMP ("req.persona.{0}.json" -f (Get-Random))
  Write-Utf8NoBom $tmp $json

  try {
    & curl.exe -sS -X POST `
      -H "X-INTERNAL-KEY: $internalKey" `
      -H "Content-Type: application/json" `
      --data-binary "@$tmp" $url
  }
  finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Db([string]$sql){
  $tmp = Join-Path $env:TEMP ("sql.persona.{0}.sql" -f (Get-Random))
  Write-Utf8NoBom $tmp $sql

  try {
    docker cp $tmp "${mysqlContainer}:/tmp/persona.sql" | Out-Null
    docker exec $mysqlContainer sh -lc "mysql -N -u$dbUser -p$dbPass $dbName < /tmp/persona.sql"
  }
  finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    docker exec $mysqlContainer sh -lc "rm -f /tmp/persona.sql" | Out-Null
  }
}

function Reset-History([long]$uid){
  Db @"
DELETE FROM study_events WHERE user_id=$uid;
DELETE FROM daily_learning WHERE user_id=$uid;
"@ | Out-Null
}

function Post([long]$uid,[string]$type){
  $json = (@{ userId=$uid; type=$type } | ConvertTo-Json -Compress)
  $resp = Curl-PostJson "$base/internal/study/events" $json

  if($LASTEXITCODE -ne 0){
    throw "POST failed. user=$uid type=$type"
  }

  if([string]::IsNullOrWhiteSpace($resp)){
    Write-Host "POST user=$uid type=$type => empty response"
    return
  }

  try {
    $obj = $resp | ConvertFrom-Json
    $ok = $obj.success
    Write-Host ("POST user={0} type={1} => {2}" -f $uid,$type,$ok)
  }
  catch {
    Write-Host ("POST user={0} type={1} => raw={2}" -f $uid,$type,$resp)
  }
}

function Shift([long]$uid,[int]$days){
  if($days -le 0){ return }

  Db @"
START TRANSACTION;

UPDATE study_events
SET created_at = DATE_SUB(created_at, INTERVAL $days DAY)
WHERE user_id=$uid
  AND DATE(created_at)=CURDATE();

DELETE dl_today
FROM daily_learning dl_today
JOIN daily_learning dl_target
  ON dl_target.user_id = dl_today.user_id
 AND dl_target.ymd = DATE_SUB(dl_today.ymd, INTERVAL $days DAY)
WHERE dl_today.user_id = $uid
  AND dl_today.ymd = CURDATE();

UPDATE daily_learning
SET ymd = DATE_SUB(ymd, INTERVAL $days DAY)
WHERE user_id=$uid
  AND ymd=CURDATE();

COMMIT;
"@ | Out-Null
}

function Seed-Phase(
  [long]$uid,
  [int]$open,
  [int]$quiz,
  [int]$wrong,
  [int]$wrongDone,
  [int]$daysAgo
){
  if($open -gt 0){
    1..$open | ForEach-Object { Post $uid "JUST_OPEN" }
  }

  if($quiz -gt 0){
    1..$quiz | ForEach-Object { Post $uid "QUIZ_SUBMIT" }
  }

  if($wrong -gt 0){
    1..$wrong | ForEach-Object { Post $uid "REVIEW_WRONG" }
  }

  if($wrongDone -gt 0){
    1..$wrongDone | ForEach-Object { Post $uid "WRONG_REVIEW_DONE" }
  }

  if($daysAgo -gt 0){
    Shift $uid $daysAgo
  }
}

function Get-Coach([long]$uid){
  $txt = Curl-Text "$base/internal/study/coach?userId=$uid"
  if($LASTEXITCODE -ne 0){
    throw "coach request failed. user=$uid"
  }
  return ($txt | ConvertFrom-Json)
}

function Get-RawSummary([long]$uid){
  $raw = Db @"
SELECT
  COUNT(*) AS total_events,
  COALESCE(SUM(type='JUST_OPEN'),0) AS opens,
  COALESCE(SUM(type='QUIZ_SUBMIT'),0) AS quiz,
  COALESCE(SUM(type='REVIEW_WRONG'),0) AS wrong,
  COALESCE(SUM(type='WRONG_REVIEW_DONE'),0) AS wrong_done,
  COUNT(DISTINCT DATE(created_at)) AS active_days
FROM study_events
WHERE user_id = $uid;
"@

  $cols = @()
  if($null -ne $raw){
    $cols = @($raw -split '\s+')
  }

  return [pscustomobject]@{
    total_events = if($cols.Length -ge 1){ [int]$cols[0] } else { 0 }
    opens        = if($cols.Length -ge 2){ [int]$cols[1] } else { 0 }
    quiz         = if($cols.Length -ge 3){ [int]$cols[2] } else { 0 }
    wrong        = if($cols.Length -ge 4){ [int]$cols[3] } else { 0 }
    wrong_done   = if($cols.Length -ge 5){ [int]$cols[4] } else { 0 }
    active_days  = if($cols.Length -ge 6){ [int]$cols[5] } else { 0 }
  }
}

function Get-PropValue($obj,[string]$name,$default=$null){
  if($null -eq $obj){ return $default }
  $p = $obj.PSObject.Properties[$name]
  if($null -eq $p){ return $default }
  if($null -eq $p.Value){ return $default }
  return $p.Value
}

function Save([long]$uid,[string]$tag,[object]$obj){
  $dir = Join-Path $PSScriptRoot "artifacts"
  if(-not (Test-Path $dir)){
    New-Item -ItemType Directory -Path $dir | Out-Null
  }

  $file = Join-Path $dir ("coach.persona.{0}.user{1}.{2}.json" -f $tag,$uid,(Get-Date -Format "yyyyMMdd-HHmmssfff"))
  ($obj | ConvertTo-Json -Depth 20) | Out-File $file -Encoding utf8
  Write-Host "saved: $file"
}

function Print-Summary([long]$uid,[string]$tag,[object]$coach,[object]$raw){
  $state = Get-PropValue $coach "state" $null
  $pred  = Get-PropValue $coach "prediction" $null
  $ev    = if($pred){ Get-PropValue $pred "evidence" $null } else { $null }

  $level      = Get-PropValue $pred  "level" "-"
  $reasonCode = Get-PropValue $pred  "reasonCode" "-"
  $nextAction = Get-PropValue $coach "nextAction" "-"

  $daysSince  = Get-PropValue $ev "daysSinceLastEvent" "-"
  $recent3d   = Get-PropValue $ev "recentEventCount3d" "-"
  $streakDays = Get-PropValue $ev "streakDays" "-"

  $eventsCnt  = Get-PropValue $state "eventsCount" 0
  $quizCnt    = Get-PropValue $state "quizSubmits" 0
  $wrongCnt   = Get-PropValue $state "wrongReviews" 0

  Write-Host ""
  Write-Host ("[PHASE] {0} user={1}" -f $tag,$uid)
  Write-Host (" level={0} reason={1} action={2}" -f $level,$reasonCode,$nextAction)
  Write-Host (" evidence: daysSince={0} recent3d={1} streak={2}" -f $daysSince,$recent3d,$streakDays)
  Write-Host (" state:    events={0} quiz={1} wrong={2}" -f $eventsCnt,$quizCnt,$wrongCnt)
  Write-Host (" raw:      total={0} open={1} quiz={2} wrong={3} wrongDone={4} activeDays={5}" -f `
    $raw.total_events,$raw.opens,$raw.quiz,$raw.wrong,$raw.wrong_done,$raw.active_days)
}

function Run-Phase([long]$uid,[string]$tag,[scriptblock]$seedFn){
  Reset-History $uid
  & $seedFn

  $coach = Get-Coach $uid
  $raw   = Get-RawSummary $uid

  Print-Summary $uid $tag $coach $raw

  $payload = [pscustomobject]@{
    tag = $tag
    userId = $uid
    coach = $coach
    raw = $raw
  }

  Save $uid $tag $payload
}

if($userIds.Length -lt 3){
  throw "userIds must contain 3 ids. ex) 31,32,33"
}

$immersedUser = $userIds[0]
$gapUser      = $userIds[1]
$wrongUser    = $userIds[2]

Write-Host ""
Write-Host "==============================" -ForegroundColor Cyan
Write-Host "PERSONA SMOKE TEST" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
Write-Host "immersedUser = $immersedUser"
Write-Host "gapUser      = $gapUser"
Write-Host "wrongUser    = $wrongUser"

# 1) 몰입형
Run-Phase $immersedUser "immersed" {
  Seed-Phase $immersedUser 1 2 0 0 2
  Seed-Phase $immersedUser 1 2 0 0 1
  Seed-Phase $immersedUser 1 3 1 1 0
}

# 2) 공백형
Run-Phase $gapUser "gap" {
  # intentionally blank
}

# 3) 오답형
Run-Phase $wrongUser "wrongpersona" {
  Seed-Phase $wrongUser 1 2 0 0 1
  Seed-Phase $wrongUser 1 3 2 0 0
}

Write-Host ""
Write-Host "==============================" -ForegroundColor Green
Write-Host "EXPECTED" -ForegroundColor Green
Write-Host "==============================" -ForegroundColor Green
Write-Host "immersed     : SAFE 또는 안정형 WARNING"
Write-Host "gap          : DANGER / HABIT_COLLAPSE 계열"
Write-Host "wrongpersona : WARNING / REVIEW_WRONG_PENDING / REVIEW_WRONG_ONE 기대"