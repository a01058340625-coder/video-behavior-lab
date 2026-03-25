param(
  [long[]]$userIds = @(5,9,10,12),

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
  $tmp = Join-Path $env:TEMP ("req.day29.{0}.json" -f (Get-Random))
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
  $tmp = Join-Path $env:TEMP ("sql.day29.{0}.sql" -f (Get-Random))
  Write-Utf8NoBom $tmp $sql

  try {
    docker cp $tmp "${mysqlContainer}:/tmp/day29.sql" | Out-Null
    docker exec $mysqlContainer sh -lc "mysql -N -u$dbUser -p$dbPass $dbName < /tmp/day29.sql"
  }
  finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    docker exec $mysqlContainer sh -lc "rm -f /tmp/day29.sql" | Out-Null
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
  $null = Curl-PostJson "$base/internal/study/events" $json
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
  Curl-Text "$base/internal/study/coach?userId=$uid" | ConvertFrom-Json
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

function Get-Ratios([object]$raw){
  $total = [double]([Math]::Max(1, $raw.total_events))
  return [pscustomobject]@{
    open_ratio  = [math]::Round(($raw.opens / $total), 2)
    quiz_ratio  = [math]::Round(($raw.quiz / $total), 2)
    wrong_ratio = [math]::Round(($raw.wrong / $total), 2)
    done_ratio  = [math]::Round(($raw.wrong_done / $total), 2)
  }
}

function Save([long]$uid,[string]$tag,[object]$obj){
  $dir = Join-Path $PSScriptRoot "artifacts"
  if(-not (Test-Path $dir)){
    New-Item -ItemType Directory -Path $dir | Out-Null
  }

  $file = Join-Path $dir ("coach.day29.{0}.user{1}.{2}.json" -f $tag,$uid,(Get-Date -Format "yyyyMMdd-HHmmssfff"))
  ($obj | ConvertTo-Json -Depth 20) | Out-File $file -Encoding utf8
}

function Get-PropValue($obj,[string]$name,$default=$null){
  if($null -eq $obj){ return $default }
  $p = $obj.PSObject.Properties[$name]
  if($null -eq $p){ return $default }
  if($null -eq $p.Value){ return $default }
  return $p.Value
}

function Print-Summary([long]$uid,[string]$tag,[object]$coach,[object]$raw,[object]$ratio){
  $p = $coach.prediction
  $e = if($p){ $p.evidence } else { $null }
  $s = $coach.state

  $level      = Get-PropValue $p "level" "-"
  $reasonCode = Get-PropValue $p "reasonCode" "-"
  $nextAction = Get-PropValue $coach "nextAction" "-"
  $daysSince  = Get-PropValue $e "daysSinceLastEvent" "-"
  $recent3d   = Get-PropValue $e "recentEventCount3d" "-"
  $streakDays = Get-PropValue $e "streakDays" "-"
  $eventsCnt  = Get-PropValue $s "eventsCount" 0
  $quizCnt    = Get-PropValue $s "quizSubmits" 0
  $wrongCnt   = Get-PropValue $s "wrongReviews" 0

  $wrongDone  = Get-PropValue $s "wrongReviewDoneCount" 0
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
  Write-Host (" ratio:    open={0} quiz={1} wrong={2} done={3}" -f `
    $ratio.open_ratio,$ratio.quiz_ratio,$ratio.wrong_ratio,$ratio.done_ratio)
}

function Run-Phase([long]$uid,[string]$tag,[scriptblock]$seedFn){
  Reset-History $uid
  & $seedFn

  $coach = Get-Coach $uid
  $raw   = Get-RawSummary $uid
  $ratio = Get-Ratios $raw

  Print-Summary $uid $tag $coach $raw $ratio

  $payload = [pscustomobject]@{
    day = 29
    tag = $tag
    userId = $uid
    coach = $coach
    raw = $raw
    ratio = $ratio
  }

  Save $uid $tag $payload
}

foreach($uid in $userIds){

  Write-Host ""
  Write-Host "==============================" -ForegroundColor Yellow
  Write-Host "DAY29 USER $uid" -ForegroundColor Yellow
  Write-Host "==============================" -ForegroundColor Yellow

  # spamopen : open 편중 + 날짜 분산
  Run-Phase $uid "spamopen" {
    Seed-Phase $uid 8  0 0 0 2
    Seed-Phase $uid 12 0 0 0 0
  }

  # quizonly : quiz 편중 + 날짜 분산
  Run-Phase $uid "quizonly" {
    Seed-Phase $uid 0 4 0 0 2
    Seed-Phase $uid 0 6 0 0 0
  }

  # wrongheavy : wrong 비중이 매우 큼
  Run-Phase $uid "wrongheavy" {
    Seed-Phase $uid 1 1 4 0 2
    Seed-Phase $uid 1 1 6 1 0
  }

  # recoverybias : wrong_done 비중이 큼
  Run-Phase $uid "recoverybias" {
    Seed-Phase $uid 1 1 2 4 2
    Seed-Phase $uid 1 1 1 6 0
  }

  # balanced : 비교용 중간 패턴
  Run-Phase $uid "balanced" {
    Seed-Phase $uid 1 2 1 1 2
    Seed-Phase $uid 1 2 1 1 0
  }

  # lowqualitymix : 열기 많고 퀴즈 적은 저품질 혼합
  Run-Phase $uid "lowqualitymix" {
    Seed-Phase $uid 5 1 0 0 2
    Seed-Phase $uid 6 1 1 0 0
  }
}

Write-Host ""
Write-Host "DAY29 TUNED DONE" -ForegroundColor Green