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

. (Join-Path $PSScriptRoot "run-days-common.ps1")

$scenarioMap = [ordered]@{
  blank      = 5
  comeback   = 9
  steady     = 6
  wrongheavy = 1
  recovery   = 10
  anomaly    = 3
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
    action = "READ_SUMMARY"
  }
  anomaly = [ordered]@{
  level  = "WARNING"
  reason = "LOW_QUALITY_OPEN"
  action = "RETRY_QUIZ"
}
}

function Get-UserByTargetId([long]$targetUserId) {
  $u = $Global:GooUsers |
    Where-Object { [long]$_.targetUserId -eq [long]$targetUserId } |
    Select-Object -First 1

  if ($null -eq $u) {
    throw "persona-map.ps1 에 targetUserId=$targetUserId 사용자가 없습니다."
  }

  return $u
}

function Reset-Users([long[]]$userIds) {
  foreach($uid in $userIds){
    docker exec $mysqlContainer mysql -uroot -proot123 $dbName -e @"
delete from study_events where user_id = $uid;
delete from daily_learning where user_id = $uid;
"@ | Out-Null
  }
}

function Get-IntOrDefault {
  param(
    [Parameter(Mandatory=$true)]$arr,
    [Parameter(Mandatory=$true)][int]$idx,
    [int]$defaultValue = 0
  )

  if ($null -ne $arr -and $arr.Count -gt $idx) {
    $v = $arr[$idx]
    if ($null -ne $v) {
      $s = "$v".Trim()
      if ($s -ne "" -and $s.ToUpper() -ne "NULL") {
        return [int]$s
      }
    }
  }

  return [int]$defaultValue
}

function Get-StrOrDefault {
  param(
    [Parameter(Mandatory=$true)]$arr,
    [Parameter(Mandatory=$true)][int]$idx,
    [string]$defaultValue = "NULL"
  )

  if ($null -ne $arr -and $arr.Count -gt $idx) {
    $v = $arr[$idx]
    if ($null -ne $v -and "$v".Trim() -ne "") {
      return [string]$v
    }
  }

  return [string]$defaultValue
}

function Parse-Row {
  param(
    [string]$line
  )

  if ([string]::IsNullOrWhiteSpace($line)) {
    $p = @()
  } else {
    $p = $line -split "`t"
  }

  return [ordered]@{
    total_events = Get-IntOrDefault -arr $p -idx 0 -defaultValue 0
    opens        = Get-IntOrDefault -arr $p -idx 1 -defaultValue 0
    quiz         = Get-IntOrDefault -arr $p -idx 2 -defaultValue 0
    wrong        = Get-IntOrDefault -arr $p -idx 3 -defaultValue 0
    wrong_done   = Get-IntOrDefault -arr $p -idx 4 -defaultValue 0
    active_days  = Get-IntOrDefault -arr $p -idx 5 -defaultValue 0
    first_day    = Get-StrOrDefault -arr $p -idx 6 -defaultValue "NULL"
    last_day     = Get-StrOrDefault -arr $p -idx 7 -defaultValue "NULL"
  }
}

function Save-CoachArtifact {
  param(
    [Parameter(Mandatory=$true)][string]$tag,
    [Parameter(Mandatory=$true)][long]$userId,
    [Parameter(Mandatory=$true)]$user
  )

  $stamp = Get-Date -Format "yyyyMMdd-HHmmssfff"
  $outFile = Join-Path $artifactsDir ("coach.day34.{0}.user{1}.{2}.json" -f $tag, $userId, $stamp)

  New-Item -ItemType Directory -Force -Path $artifactsDir | Out-Null

  $coachResp = curl.exe -s `
    -H ("X-Internal-Key: {0}" -f $internalKey) `
    "$base/internal/study/coach?userId=$userId"

  Write-Host "[DEBUG] coachResp =>" -ForegroundColor DarkGray
  Write-Host $coachResp -ForegroundColor DarkGray

  $obj = $coachResp | ConvertFrom-Json

  if ($null -eq $obj -or $null -eq $obj.prediction -or $null -eq $obj.nextAction) {
    throw ("internal coach 응답 형식 이상 userId={0}" -f $userId)
  }

  $rawTotal = docker exec $mysqlContainer mysql -N -B -uroot -proot123 $dbName -e @"
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
where user_id = $userId;
"@

  $rawToday = docker exec $mysqlContainer mysql -N -B -uroot -proot123 $dbName -e @"
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
  and date(created_at)=curdate();
"@

  $totalLine = ($rawTotal | Select-Object -First 1)
  $todayLine = ($rawToday | Select-Object -First 1)

  if ($null -eq $totalLine) { $totalLine = "" }
  if ($null -eq $todayLine) { $todayLine = "" }

  $totalMap = Parse-Row -line ($totalLine.ToString().Trim())
  $todayMap = Parse-Row -line ($todayLine.ToString().Trim())

  $artifact = [ordered]@{
    day = 34
    tag = $tag
    userId = $userId
    generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    expected = $expectedMap[$tag]
    coach = $obj
    raw = [ordered]@{
      total = $totalMap
      today = $todayMap
    }
  }

  ($artifact | ConvertTo-Json -Depth 10) | Set-Content -Encoding utf8 $outFile
  Write-Host ("[OK]  saved => {0}" -f $outFile) -ForegroundColor Green
}

function Seed-Blank($user) {
  Write-Host "[SCENARIO] blank user=$($user.targetUserId)" -ForegroundColor Yellow
}

function Seed-Comeback($user) {
  Write-Host "[SCENARIO] comeback user=$($user.targetUserId)" -ForegroundColor Yellow
  Invoke-UserScenario -user $user -justOpen 1 -quiz 0 -wrong 0 -wrongDone 0 -daysAgo 4 -base $base -tag "day34"
  Invoke-UserScenario -user $user -justOpen 1 -quiz 0 -wrong 0 -wrongDone 0 -daysAgo 3 -base $base -tag "day34"
  Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 0 -wrongDone 0 -daysAgo 0 -base $base -tag "day34"
}

function Seed-Steady($user) {
  Write-Host "[SCENARIO] steady user=$($user.targetUserId)" -ForegroundColor Yellow
  4..0 | ForEach-Object {
    $d = $_
    $quiz = if ($d -eq 0) { 3 } else { 2 }
    Invoke-UserScenario -user $user -justOpen 1 -quiz $quiz -wrong 0 -wrongDone 0 -daysAgo $d -base $base -tag "day34"
  }
}

function Seed-WrongHeavy($user) {
  Write-Host "[SCENARIO] wrongheavy user=$($user.targetUserId)" -ForegroundColor Yellow
  Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 2 -wrongDone 0 -daysAgo 2 -base $base -tag "day34"
  Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 2 -wrongDone 0 -daysAgo 1 -base $base -tag "day34"
  Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 5 -wrongDone 1 -daysAgo 0 -base $base -tag "day34"
}

function Seed-Recovery($user) {
  Write-Host "[SCENARIO] recovery user=$($user.targetUserId)" -ForegroundColor Yellow
  Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 2 -wrongDone 0 -daysAgo 2 -base $base -tag "day34"
  Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 1 -wrongDone 2 -daysAgo 1 -base $base -tag "day34"
  Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 1 -wrongDone 4 -daysAgo 0 -base $base -tag "day34"
}

function Seed-Anomaly($user) {
  Write-Host "[SCENARIO] anomaly user=$($user.targetUserId)" -ForegroundColor Yellow
  Invoke-UserScenario -user $user -justOpen 6 -quiz 0 -wrong 0 -wrongDone 0 -daysAgo 0 -base $base -tag "day34"
}

if($mode -in @("seed","all")){
  Write-Banner "DAY34 PREDICTION ACCURACY EVALUATION"

  Reset-Users -userIds ($scenarioMap.Values | ForEach-Object { [long]$_ })

  Seed-Blank      (Get-UserByTargetId $scenarioMap.blank)
  Seed-Comeback   (Get-UserByTargetId $scenarioMap.comeback)
  Seed-Steady     (Get-UserByTargetId $scenarioMap.steady)
  Seed-WrongHeavy (Get-UserByTargetId $scenarioMap.wrongheavy)
  Seed-Recovery   (Get-UserByTargetId $scenarioMap.recovery)
  Seed-Anomaly    (Get-UserByTargetId $scenarioMap.anomaly)

  Show-TodayDbSummary
}

if($mode -in @("verify","all")){
  Write-Banner "DAY34 COACH ARTIFACT SAVE"

  foreach($tag in $scenarioMap.Keys){
    $uid = [long]$scenarioMap[$tag]
    $user = Get-UserByTargetId $uid
    Save-CoachArtifact -tag $tag -userId $uid -user $user
  }

  Write-Banner "DAY34 DONE"
}