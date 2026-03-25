param(
  [long[]]$userIds = @(13),

  [string]$base = "http://127.0.0.1:8083",
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

function Db([string]$sql){
  $tmp = Join-Path $env:TEMP ("sql.recovery.{0}.sql" -f (Get-Random))
  $containerTmp = "/tmp/recovery.$([guid]::NewGuid().ToString('N')).sql"

  $cleanSql = $sql.Trim()

  Write-Utf8NoBom $tmp $cleanSql

  try {
    & docker cp $tmp "${mysqlContainer}:$containerTmp" | Out-Null
    & docker exec $mysqlContainer sh -lc "mysql -N -u$dbUser -p$dbPass $dbName < $containerTmp"
  }
  finally {
    & docker exec $mysqlContainer sh -lc "rm -f $containerTmp" | Out-Null
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Curl-Text([string]$url){
  & curl.exe -sS -H "X-INTERNAL-KEY: $internalKey" $url
}

function Curl-PostJson([string]$url,[string]$json){
  $tmp = Join-Path $env:TEMP ("req.recovery.{0}.json" -f (Get-Random))
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

function Reset-History([long]$uid){
  Db @"
DELETE FROM study_events   WHERE user_id = $uid;
DELETE FROM daily_learning WHERE user_id = $uid;
"@ | Out-Null
}

function Post([long]$uid,[string]$type){
  $json = (@{ userId = $uid; type = $type } | ConvertTo-Json -Compress)
  $res = Curl-PostJson "$base/internal/study/events" $json
  if (-not [string]::IsNullOrWhiteSpace($res)) {
    $res | Out-Host
  }
}

function Shift-TodayRows([long]$uid,[int]$daysAgo){
  if($daysAgo -le 0){ return }

  Db @"
START TRANSACTION;

UPDATE study_events
SET created_at = DATE_SUB(created_at, INTERVAL $daysAgo DAY)
WHERE user_id = $uid
  AND DATE(created_at) = CURDATE();

DELETE dl_today
FROM daily_learning dl_today
JOIN daily_learning dl_target
  ON dl_target.user_id = dl_today.user_id
 AND dl_target.ymd = DATE_SUB(dl_today.ymd, INTERVAL $daysAgo DAY)
WHERE dl_today.user_id = $uid
  AND dl_today.ymd = CURDATE();

UPDATE daily_learning
SET ymd = DATE_SUB(ymd, INTERVAL $daysAgo DAY)
WHERE user_id = $uid
  AND ymd = CURDATE();

COMMIT;
"@ | Out-Null
}

function Seed-Events(
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
    Shift-TodayRows $uid $daysAgo
  }
}

function Get-Coach([long]$uid){
  $txt = Curl-Text "$base/internal/study/coach?userId=$uid"
  if([string]::IsNullOrWhiteSpace($txt)){ throw "coach response empty (user=$uid)" }
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

  [pscustomobject]@{
    total_events = if($cols.Length -ge 1){ [int]$cols[0] } else { 0 }
    opens        = if($cols.Length -ge 2){ [int]$cols[1] } else { 0 }
    quiz         = if($cols.Length -ge 3){ [int]$cols[2] } else { 0 }
    wrong        = if($cols.Length -ge 4){ [int]$cols[3] } else { 0 }
    wrong_done   = if($cols.Length -ge 5){ [int]$cols[4] } else { 0 }
    active_days  = if($cols.Length -ge 6){ [int]$cols[5] } else { 0 }
  }
}

function Save-Artifact([long]$uid,[string]$tag,[object]$payload){
  $dir = Join-Path $PSScriptRoot "artifacts"
  if(-not (Test-Path $dir)){
    New-Item -ItemType Directory -Path $dir | Out-Null
  }

  $file = Join-Path $dir ("coach.recovery.{0}.user{1}.{2}.json" -f $tag,$uid,(Get-Date -Format "yyyyMMdd-HHmmssfff"))
  ($payload | ConvertTo-Json -Depth 20) | Out-File $file -Encoding utf8
  Write-Host "saved: $file" -ForegroundColor Green
}

function Get-PropValue($obj,[string]$name,$default=$null){
  if($null -eq $obj){ return $default }
  $p = $obj.PSObject.Properties[$name]
  if($null -eq $p){ return $default }
  if($null -eq $p.Value){ return $default }
  return $p.Value
}

function Print-Summary([long]$uid,[string]$tag,[object]$coach,[object]$raw){
  # coach가 { success, message, data } 형태면 data 사용
  # 아니면 coach 자체를 바로 사용
  $dataProp = $coach.PSObject.Properties["data"]
  if($null -ne $dataProp -and $null -ne $dataProp.Value){
    $data = $dataProp.Value
  }
  else {
    $data = $coach
  }

  $p = Get-PropValue $data "prediction" $null
  $e = if($null -ne $p){ Get-PropValue $p "evidence" $null } else { $null }
  $s = Get-PropValue $data "state" $null
  $nextAction = Get-PropValue $data "nextAction" "-"

  $level      = Get-PropValue $p "level" "-"
  $reasonCode = Get-PropValue $p "reasonCode" "-"
  $daysSince  = Get-PropValue $e "daysSinceLastEvent" "-"
  $recent3d   = Get-PropValue $e "recentEventCount3d" "-"
  $streakDays = Get-PropValue $e "streakDays" "-"
  $eventsCnt  = Get-PropValue $s "eventsCount" 0
  $quizCnt    = Get-PropValue $s "quizSubmits" 0
  $wrongCnt   = Get-PropValue $s "wrongReviews" 0

  $wrongDone  = Get-PropValue $s "wrongReviewDone" $null
  if($null -eq $wrongDone){
    $wrongDone = Get-PropValue $s "wrongReviewsDone" 0
  }

  Write-Host ""
  Write-Host "[PHASE] $tag user=$uid" -ForegroundColor Cyan
  Write-Host (" level={0} reason={1} action={2}" -f $level,$reasonCode,$nextAction)
  Write-Host (" evidence: daysSince={0} recent3d={1} streak={2}" -f $daysSince,$recent3d,$streakDays)
  Write-Host (" state:    events={0} quiz={1} wrong={2} wrongDone={3}" -f $eventsCnt,$quizCnt,$wrongCnt,$wrongDone)
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
    tag    = $tag
    userId = $uid
    raw    = $raw
    coach  = $coach
  }

  Save-Artifact $uid $tag $payload
}

foreach($uid in $userIds){
  Write-Host ""
  Write-Host "==============================" -ForegroundColor Yellow
  Write-Host "RECOVERY BASIC USER $uid" -ForegroundColor Yellow
  Write-Host "==============================" -ForegroundColor Yellow

  # baseline: 완전 공백
  Run-Phase $uid "baseline" {
    # reset만 하고 아무것도 안 넣음
  }

  # recoveryA: 최소 복구
  Run-Phase $uid "recoveryA" {
    Seed-Events $uid 1 1 0 0 0
  }

  # recoveryB: quiz 조금 더
  Run-Phase $uid "recoveryB" {
    Seed-Events $uid 1 2 0 0 0
  }

  # recoveryC: 2일 연속 복구
  Run-Phase $uid "recoveryC" {
    Seed-Events $uid 1 1 0 0 1
    Seed-Events $uid 1 1 0 0 0
  }

  # recoveryD: 복구 + 오답 처리
  Run-Phase $uid "recoveryD" {
    Seed-Events $uid 1 2 1 1 0
  }
}

Write-Host ""
Write-Host "RECOVERY BASIC DONE" -ForegroundColor Green