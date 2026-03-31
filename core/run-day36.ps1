param(
  [ValidateSet("seed","verify","all")]
  [string]$mode = "all",

  [string]$base = "http://127.0.0.1:8084",
  [string]$internalKey = "goosage-dev",
  [string]$artifactsDir = "C:\dev\loosegoose\goosage-scripts\core\artifacts",

  [string]$mysqlContainer = "goosage-mysql",
  [string]$dbName = "goosage"
)

chcp 65001 > $null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Banner($text) {
  Write-Host ""
  Write-Host "========================================" -ForegroundColor DarkCyan
  Write-Host " $text" -ForegroundColor Cyan
  Write-Host "========================================" -ForegroundColor DarkCyan
}

$scenarioMap = [ordered]@{
  blank         = 5
  comeback      = 9
  steady        = 6
  wrongheavy    = 1
  recovery      = 10
  recoverysafe  = 3
}

$expectedMap = [ordered]@{
  blank = [ordered]@{
    level  = "DANGER"
    reason = "HABIT_COLLAPSE"
    action = "READ_SUMMARY"
  }
  comeback = [ordered]@{
    level  = "WARNING"
    reason = "MINIMUM_ACTION"
    action = "JUST_OPEN"
  }
  steady = [ordered]@{
    level  = "SAFE"
    reason = "HABIT_STABLE"
    action = "READ_SUMMARY"
  }
  wrongheavy = [ordered]@{
    level  = "WARNING"
    reason = "WRONG_HEAVY"
    action = "REVIEW_WRONG_ONE"
  }
  recovery = [ordered]@{
    level  = "WARNING"
    reason = "RECOVERY_PROGRESS"
    action = "REVIEW_WRONG_ONE"
  }
  recoverysafe = [ordered]@{
    level  = "SAFE"
    reason = "RECOVERY_SAFE"
    action = "READ_SUMMARY"
  }
}

function Reset-Users([long[]]$userIds) {
  foreach($uid in $userIds){
    docker exec $mysqlContainer mysql -uroot -proot123 $dbName -e @"
delete from study_events where user_id = $uid;
delete from daily_learning where user_id = $uid;
"@ | Out-Null
  }
}

function Post-InternalEvent {
  param(
    [Parameter(Mandatory=$true)][long]$userId,
    [Parameter(Mandatory=$true)][ValidateSet("JUST_OPEN","QUIZ_SUBMIT","REVIEW_WRONG","WRONG_REVIEW_DONE")][string]$type
  )

  $body = @{
    userId = $userId
    type   = $type
  } | ConvertTo-Json -Compress

  $resp = Invoke-RestMethod `
    -Method POST `
    -Uri "$base/internal/study/events" `
    -Headers @{ "X-Internal-Key" = $internalKey } `
    -ContentType "application/json" `
    -Body $body

  if ($null -eq $resp -or $resp.success -ne $true) {
    throw "internal event insert 실패 userId=$userId type=$type"
  }
}

function Add-Events {
  param(
    [Parameter(Mandatory=$true)][long]$userId,
    [int]$justOpen = 0,
    [int]$quiz = 0,
    [int]$wrong = 0,
    [int]$wrongDone = 0,
    [int]$daysAgo = 0
  )

  for($i=0; $i -lt $justOpen; $i++){ Post-InternalEvent -userId $userId -type "JUST_OPEN" }
  for($i=0; $i -lt $quiz; $i++){ Post-InternalEvent -userId $userId -type "QUIZ_SUBMIT" }
  for($i=0; $i -lt $wrong; $i++){ Post-InternalEvent -userId $userId -type "REVIEW_WRONG" }
  for($i=0; $i -lt $wrongDone; $i++){ Post-InternalEvent -userId $userId -type "WRONG_REVIEW_DONE" }

  if ($daysAgo -gt 0) {
    docker exec $mysqlContainer mysql -uroot -proot123 $dbName -e @"
update study_events
set created_at = date_sub(created_at, interval $daysAgo day)
where user_id = $userId
  and date(created_at) = curdate();
"@ | Out-Null
  }
}

function Get-Coach([long]$userId) {
  return Invoke-RestMethod `
    -Method GET `
    -Uri "$base/internal/study/coach?userId=$userId" `
    -Headers @{ "X-Internal-Key" = $internalKey }
}

function Parse-Row {
  param([string]$line)

  $p = @()
  if (-not [string]::IsNullOrWhiteSpace($line)) {
    $p = $line -split "`t"
  }

  function Get-Int([object[]]$arr, [int]$idx, [int]$defaultValue = 0) {
    if ($null -ne $arr -and $arr.Count -gt $idx) {
      $v = $arr[$idx]
      if ($null -ne $v -and "$v".Trim() -ne "" -and "$v".Trim().ToUpper() -ne "NULL") {
        return [int]$v
      }
    }
    return [int]$defaultValue
  }

  function Get-Str([object[]]$arr, [int]$idx, [string]$defaultValue = "NULL") {
    if ($null -ne $arr -and $arr.Count -gt $idx) {
      $v = $arr[$idx]
      if ($null -ne $v -and "$v".Trim() -ne "") {
        return [string]$v
      }
    }
    return [string]$defaultValue
  }

  return [ordered]@{
    total_events = Get-Int $p 0 0
    opens        = Get-Int $p 1 0
    quiz         = Get-Int $p 2 0
    wrong        = Get-Int $p 3 0
    wrong_done   = Get-Int $p 4 0
    active_days  = Get-Int $p 5 0
    first_day    = Get-Str $p 6 "NULL"
    last_day     = Get-Str $p 7 "NULL"
  }
}

function Get-RawRow {
  param(
    [Parameter(Mandatory=$true)][long]$userId,
    [switch]$TodayOnly
  )

  $whereToday = ""
  if ($TodayOnly) {
    $whereToday = "and date(created_at)=curdate()"
  }

  $raw = docker exec $mysqlContainer mysql -N -B -uroot -proot123 $dbName -e @"
select
  count(*) as total_events,
  coalesce(sum(type='JUST_OPEN'), 0) as opens,
  coalesce(sum(type='QUIZ_SUBMIT'), 0) as quiz,
  coalesce(sum(type='REVIEW_WRONG'), 0) as wrong,
  coalesce(sum(type='WRONG_REVIEW_DONE'), 0) as wrong_done,
  count(distinct date(created_at)) as active_days,
  coalesce(date_format(min(created_at),'%Y-%m-%d'),'NULL') as first_day,
  coalesce(date_format(max(created_at),'%Y-%m-%d'),'NULL') as last_day
from study_events
where user_id = $userId
  $whereToday;
"@

  $line = ($raw | Select-Object -First 1)
  if ($null -eq $line) { $line = "" }

  return Parse-Row -line ($line.ToString().Trim())
}

function Save-CoachArtifact {
  param(
    [Parameter(Mandatory=$true)][string]$tag,
    [Parameter(Mandatory=$true)][long]$userId
  )

  $stamp = Get-Date -Format "yyyyMMdd-HHmmssfff"
  $outFile = Join-Path $artifactsDir ("coach.day36.{0}.user{1}.{2}.json" -f $tag, $userId, $stamp)

  New-Item -ItemType Directory -Force -Path $artifactsDir | Out-Null

  $coach = Get-Coach -userId $userId

  Write-Host "[DEBUG] coachResp =>" -ForegroundColor DarkGray
  ($coach | ConvertTo-Json -Depth 10 -Compress) | Write-Host -ForegroundColor DarkGray

  $artifact = [ordered]@{
    day = 36
    tag = $tag
    userId = $userId
    generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    expected = $expectedMap[$tag]
    coach = $coach
    raw = [ordered]@{
      total = (Get-RawRow -userId $userId)
      today = (Get-RawRow -userId $userId -TodayOnly)
    }
  }

  ($artifact | ConvertTo-Json -Depth 10) | Set-Content -Encoding utf8 $outFile
  Write-Host ("[OK]  saved => {0}" -f $outFile) -ForegroundColor Green
}

function Show-TodayDbSummary {
  Write-Banner "TODAY DB SUMMARY"

  docker exec $mysqlContainer mysql -uroot -proot123 $dbName -e @"
select user_id, type, count(*) cnt
from study_events
where date(created_at)=curdate()
group by user_id, type
order by user_id, type;
"@
}

function Seed-Blank {
  param([long]$userId)
  Write-Host "[SCENARIO] blank user=$userId" -ForegroundColor Yellow
  # 아무 이벤트 없음 = 붕괴 상태
}

function Seed-Comeback {
  param([long]$userId)
  Write-Host "[SCENARIO] comeback user=$userId" -ForegroundColor Yellow
  Add-Events -userId $userId -justOpen 1 -daysAgo 4
  Add-Events -userId $userId -justOpen 1 -daysAgo 3
  Add-Events -userId $userId -justOpen 1 -daysAgo 0
}

function Seed-Steady {
  param([long]$userId)
  Write-Host "[SCENARIO] steady user=$userId" -ForegroundColor Yellow
  4..0 | ForEach-Object {
    $d = $_
    $quiz = if ($d -eq 0) { 3 } else { 2 }
    Add-Events -userId $userId -justOpen 1 -quiz $quiz -daysAgo $d
  }
}

function Seed-WrongHeavy {
  param([long]$userId)
  Write-Host "[SCENARIO] wrongheavy user=$userId" -ForegroundColor Yellow
  Add-Events -userId $userId -justOpen 1 -quiz 1 -wrong 2 -daysAgo 2
  Add-Events -userId $userId -justOpen 1 -quiz 1 -wrong 2 -daysAgo 1
  Add-Events -userId $userId -justOpen 1 -quiz 1 -wrong 5 -wrongDone 1 -daysAgo 0
}

function Seed-Recovery {
  param([long]$userId)
  Write-Host "[SCENARIO] recovery user=$userId" -ForegroundColor Yellow
  Add-Events -userId $userId -justOpen 1 -quiz 1 -wrong 3 -wrongDone 0 -daysAgo 2
  Add-Events -userId $userId -justOpen 1 -quiz 1 -wrong 2 -wrongDone 2 -daysAgo 1
  Add-Events -userId $userId -justOpen 1 -quiz 1 -wrong 1 -wrongDone 4 -daysAgo 0
}

function Seed-RecoverySafe {
  param([long]$userId)
  Write-Host "[SCENARIO] recoverysafe user=$userId" -ForegroundColor Yellow
  Add-Events -userId $userId -justOpen 1 -quiz 2 -wrong 2 -wrongDone 2 -daysAgo 2
  Add-Events -userId $userId -justOpen 1 -quiz 2 -wrong 1 -wrongDone 3 -daysAgo 1
  Add-Events -userId $userId -justOpen 1 -quiz 2 -wrong 0 -wrongDone 3 -daysAgo 0
}

if($mode -in @("seed","all")){
  Write-Banner "DAY36 RECOVERY ALGORITHM IMPROVEMENT"

  Reset-Users -userIds ($scenarioMap.Values | ForEach-Object { [long]$_ })

  Seed-Blank        -userId ([long]$scenarioMap.blank)
  Seed-Comeback     -userId ([long]$scenarioMap.comeback)
  Seed-Steady       -userId ([long]$scenarioMap.steady)
  Seed-WrongHeavy   -userId ([long]$scenarioMap.wrongheavy)
  Seed-Recovery     -userId ([long]$scenarioMap.recovery)
  Seed-RecoverySafe -userId ([long]$scenarioMap.recoverysafe)

  Show-TodayDbSummary
}

if($mode -in @("verify","all")){
  Write-Banner "DAY36 COACH ARTIFACT SAVE"

  foreach($tag in $scenarioMap.Keys){
    $uid = [long]$scenarioMap[$tag]
    Save-CoachArtifact -tag $tag -userId $uid
  }

  Write-Banner "DAY36 DONE"
}