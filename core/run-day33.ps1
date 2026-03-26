param(
  [ValidateSet("seed","verify","all")]
  [string]$mode = "all",

  [string]$base = "http://127.0.0.1:8084",
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
  steady     = 10
  wrongheavy = 12
  recovery   = 13
  anomaly    = 14
}

function Get-UserByTargetId([long]$targetUserId) {
  $u = $Global:GooUsers | Where-Object { [long]$_.targetUserId -eq [long]$targetUserId } | Select-Object -First 1
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

function Save-CoachArtifact {
  param(
    [Parameter(Mandatory=$true)][string]$tag,
    [Parameter(Mandatory=$true)][long]$userId,
    [Parameter(Mandatory=$true)]$user
  )

  $stamp = Get-Date -Format "yyyyMMdd-HHmmssfff"
  $outFile = Join-Path $artifactsDir ("coach.day33.{0}.user{1}.{2}.json" -f $tag, $userId, $stamp)

  New-Item -ItemType Directory -Force -Path $artifactsDir | Out-Null

  $cookie = Join-Path $PSScriptRoot ("cookies\cookie.u{0}.txt" -f $user.loginUserNo)
  if (Test-Path $cookie) { Remove-Item $cookie -Force }

  $loginReq = Join-Path $PSScriptRoot "..\samples\http-auth-login.req.json"
  if (-not (Test-Path $loginReq)) {
    $loginReq = Join-Path $PSScriptRoot "..\samples\http-auth-login.fresh.req.json"
  }
  if (-not (Test-Path $loginReq)) {
    throw "로그인 샘플 파일을 찾을 수 없습니다."
  }

  $rawLogin = Get-Content $loginReq -Raw -Encoding utf8
  $loginBody = $rawLogin -replace '"email"\s*:\s*"[^"]+"', ('"email":"u{0}@goosage.test"' -f $user.loginUserNo)
  $loginBody = $loginBody -replace '"password"\s*:\s*"[^"]+"', '"password":"1234"'

  $null = curl.exe -s -c $cookie -b $cookie `
    -H "Content-Type: application/json" `
    -X POST "$base/auth/login" `
    --data-raw $loginBody

  $coachResp = curl.exe -s -c $cookie -b $cookie "$base/study/coach"
  $obj = $coachResp | ConvertFrom-Json

  $rawTotal = docker exec $mysqlContainer mysql -N -B -uroot -proot123 $dbName -e @"
select
  count(*) as total_events,
  sum(type='JUST_OPEN') as opens,
  sum(type='QUIZ_SUBMIT') as quiz,
  sum(type='REVIEW_WRONG') as wrong,
  sum(type='WRONG_REVIEW_DONE') as wrong_done,
  count(distinct date(created_at)) as active_days,
  coalesce(date_format(min(created_at),'%Y-%m-%d'),'NULL') as first_day,
  coalesce(date_format(max(created_at),'%Y-%m-%d'),'NULL') as last_day
from study_events
where user_id = $userId;
"@

  $rawToday = docker exec $mysqlContainer mysql -N -B -uroot -proot123 $dbName -e @"
select
  count(*) as total_events,
  sum(type='JUST_OPEN') as opens,
  sum(type='QUIZ_SUBMIT') as quiz,
  sum(type='REVIEW_WRONG') as wrong,
  sum(type='WRONG_REVIEW_DONE') as wrong_done,
  count(distinct date(created_at)) as active_days,
  coalesce(date_format(min(created_at),'%Y-%m-%d'),'NULL') as first_day,
  coalesce(date_format(max(created_at),'%Y-%m-%d'),'NULL') as last_day
from study_events
where user_id = $userId
  and date(created_at)=curdate();
"@

  function Parse-Row($line){
    $p = $line -split "`t"
    return [ordered]@{
      total_events = [int]($p[0] ?? 0)
      opens        = [int]($p[1] ?? 0)
      quiz         = [int]($p[2] ?? 0)
      wrong        = [int]($p[3] ?? 0)
      wrong_done   = [int]($p[4] ?? 0)
      active_days  = [int]($p[5] ?? 0)
      first_day    = ($p[6] ?? "NULL")
      last_day     = ($p[7] ?? "NULL")
    }
  }

  $totalMap = Parse-Row (($rawTotal | Select-Object -First 1).Trim())
  $todayMap = Parse-Row (($rawToday | Select-Object -First 1).Trim())

  $artifact = [ordered]@{
    day = 33
    tag = $tag
    userId = $userId
    generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    coach = $obj.data
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
  Invoke-UserScenario -user $user -justOpen 1 -quiz 0 -wrong 0 -wrongDone 0 -daysAgo 6 -base $base -tag "day33"
  Invoke-UserScenario -user $user -justOpen 1 -quiz 0 -wrong 0 -wrongDone 0 -daysAgo 5 -base $base -tag "day33"
  Invoke-UserScenario -user $user -justOpen 1 -quiz 0 -wrong 0 -wrongDone 0 -daysAgo 4 -base $base -tag "day33"
  Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 0 -wrongDone 0 -daysAgo 0 -base $base -tag "day33"
}

function Seed-Steady($user) {
  Write-Host "[SCENARIO] steady user=$($user.targetUserId)" -ForegroundColor Yellow
  6..0 | ForEach-Object {
    $d = $_
    $quiz = if ($d -eq 0) { 3 } else { 2 }
    Invoke-UserScenario -user $user -justOpen 1 -quiz $quiz -wrong 0 -wrongDone 0 -daysAgo $d -base $base -tag "day33"
  }
}

function Seed-WrongHeavy($user) {
  Write-Host "[SCENARIO] wrongheavy user=$($user.targetUserId)" -ForegroundColor Yellow
  Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 2 -wrongDone 0 -daysAgo 4 -base $base -tag "day33"
  Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 3 -wrongDone 0 -daysAgo 3 -base $base -tag "day33"
  Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 3 -wrongDone 0 -daysAgo 2 -base $base -tag "day33"
  Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 4 -wrongDone 0 -daysAgo 1 -base $base -tag "day33"
  Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 5 -wrongDone 1 -daysAgo 0 -base $base -tag "day33"
}

function Seed-Recovery($user) {
  Write-Host "[SCENARIO] recovery user=$($user.targetUserId)" -ForegroundColor Yellow
  Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 3 -wrongDone 0 -daysAgo 4 -base $base -tag "day33"
  Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 2 -wrongDone 1 -daysAgo 3 -base $base -tag "day33"
  Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 2 -wrongDone 2 -daysAgo 2 -base $base -tag "day33"
  Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 1 -wrongDone 3 -daysAgo 1 -base $base -tag "day33"
  Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 1 -wrongDone 4 -daysAgo 0 -base $base -tag "day33"
}

function Seed-Anomaly($user) {
  Write-Host "[SCENARIO] anomaly user=$($user.targetUserId)" -ForegroundColor Yellow
  Invoke-UserScenario -user $user -justOpen 6 -quiz 0 -wrong 0 -wrongDone 0 -daysAgo 2 -base $base -tag "day33"
  Invoke-UserScenario -user $user -justOpen 7 -quiz 0 -wrong 0 -wrongDone 0 -daysAgo 1 -base $base -tag "day33"
  Invoke-UserScenario -user $user -justOpen 8 -quiz 0 -wrong 0 -wrongDone 0 -daysAgo 0 -base $base -tag "day33"
}

if($mode -in @("seed","all")){
  Write-Banner "DAY33 LONG-TERM PATTERN EXPERIMENT"

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
  Write-Banner "DAY33 COACH ARTIFACT SAVE"

  foreach($tag in $scenarioMap.Keys){
    $uid = [long]$scenarioMap[$tag]
    $user = Get-UserByTargetId $uid
    Save-CoachArtifact -tag $tag -userId $uid -user $user
  }

  Write-Banner "DAY33 DONE"
}