param(
  [string]$artifactsDir = "C:\dev\loosegoose\goosage-scripts\core\artifacts",
  [long[]]$userIds = @(5, 9, 10, 12, 13, 14)
)

chcp 65001 > $null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$tagMap = @{ }
$tagMap[[long]5]  = "blank"
$tagMap[[long]9]  = "comeback"
$tagMap[[long]10] = "steady"
$tagMap[[long]12] = "wrongheavy"
$tagMap[[long]13] = "recovery"
$tagMap[[long]14] = "anomaly"

function Safe-Get($obj,[string]$path){
  $cur = $obj
  foreach($p in ($path -split "\.")){
    if($null -eq $cur){ return $null }
    if($cur.PSObject.Properties.Name -contains $p){
      $cur = $cur.$p
    }
    else {
      return $null
    }
  }
  return $cur
}

function Safe-Get-Any($obj,[string[]]$paths){
  foreach($path in $paths){
    $v = Safe-Get $obj $path
    if($null -ne $v){ return $v }
  }
  return $null
}

function Pick-Latest([System.IO.FileInfo[]]$files,[string]$tag,[long]$uid){
  $matched = @(
    $files |
    Where-Object { $_.Name -match "^coach\.day31\.(blank|comeback|steady|wrongheavy|recovery|anomaly)\.user\d+\.\d{8}-\d{9}\.json$" } |
    Where-Object { $_.Name -match ("^coach\.day31\.{0}\.user{1}\.\d{{8}}-\d{{9}}\.json$" -f [regex]::Escape($tag), $uid) } |
    Sort-Object LastWriteTime -Descending
  )

  if($matched.Length -gt 0){ return $matched[0] }
  return $null
}

function Load-JsonFile([System.IO.FileInfo]$file){
  Get-Content $file.FullName -Raw -Encoding utf8 | ConvertFrom-Json
}

function To-Int($v,[int]$default=0){
  if($null -eq $v){ return $default }
  try { return [int]$v } catch { return $default }
}

function To-Double($v,[double]$default=0.0){
  if($null -eq $v){ return $default }
  try { return [double]$v } catch { return $default }
}

function Same-Decision($aLevel,$aReason,$aAction,$bLevel,$bReason,$bAction){
  return (
    $aLevel  -eq $bLevel  -and
    $aReason -eq $bReason -and
    $aAction -eq $bAction
  )
}

$files = @(
  Get-ChildItem $artifactsDir -File -Filter "*.json" |
  Where-Object { $_.Name -match "^coach\.day31\.(blank|comeback|steady|wrongheavy|recovery|anomaly)\.user\d+\.\d{8}-\d{9}\.json$" }
)

$rows = @()

foreach($uid in $userIds){
  if(-not $tagMap.ContainsKey([long]$uid)){ continue }

  $tag = [string]$tagMap[[long]$uid]
  $file = Pick-Latest $files $tag ([long]$uid)
  if($null -eq $file){ continue }

  $obj = Load-JsonFile $file

  $rows += [pscustomobject]@{
    userId = [long]$uid
    tag = $tag

    total_events = Safe-Get $obj "raw.total.total_events"
    opens        = Safe-Get $obj "raw.total.opens"
    quiz         = Safe-Get $obj "raw.total.quiz"
    wrong        = Safe-Get $obj "raw.total.wrong"
    wrong_done   = Safe-Get $obj "raw.total.wrong_done"
    active_days  = Safe-Get $obj "raw.total.active_days"
    first_day    = Safe-Get $obj "raw.total.first_day"
    last_day     = Safe-Get $obj "raw.total.last_day"

    today_events      = Safe-Get $obj "raw.today.total_events"
    today_opens       = Safe-Get $obj "raw.today.opens"
    today_quiz        = Safe-Get $obj "raw.today.quiz"
    today_wrong       = Safe-Get $obj "raw.today.wrong"
    today_wrong_done  = Safe-Get $obj "raw.today.wrong_done"
    today_active_days = Safe-Get $obj "raw.today.active_days"
    today_first_day   = Safe-Get $obj "raw.today.first_day"
    today_last_day    = Safe-Get $obj "raw.today.last_day"

    coach_level  = Safe-Get $obj "coach.prediction.level"
    coach_reason = Safe-Get $obj "coach.prediction.reasonCode"
    coach_action = Safe-Get $obj "coach.nextAction"

    coach_events3d   = Safe-Get $obj "coach.prediction.evidence.recentEventCount3d"
    coach_daysSince  = Safe-Get $obj "coach.prediction.evidence.daysSinceLastEvent"
    coach_streak     = Safe-Get $obj "coach.prediction.evidence.streakDays"

    state_events    = Safe-Get $obj "coach.state.eventsCount"
    state_quiz      = Safe-Get $obj "coach.state.quizSubmits"
    state_wrong     = Safe-Get $obj "coach.state.wrongReviews"
    state_wrongDone = Safe-Get-Any $obj @(
      "coach.state.wrongReviewDoneCount",
      "coach.state.wrongReviewDone",
      "coach.state.wrongReviewsDone"
    )
  }
}

if($rows.Length -eq 0){
  Write-Host ""
  Write-Host "[FAIL] No valid day31 data found." -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "==== DAY31 PERSONA AUTO SIM SUMMARY ====" -ForegroundColor Cyan
$rows | Select-Object `
  userId, tag,
  total_events, opens, quiz, wrong, wrong_done, active_days,
  today_events, today_opens, today_quiz, today_wrong, today_wrong_done, today_active_days,
  coach_events3d, coach_daysSince, coach_streak,
  state_events, state_quiz, state_wrong, state_wrongDone,
  coach_level, coach_reason, coach_action |
  Format-Table -AutoSize

Write-Host ""
Write-Host "==== DAY31 DATE RANGE CHECK ====" -ForegroundColor Cyan
$rows | Select-Object `
  userId, tag, first_day, last_day, today_first_day, today_last_day |
  Format-Table -AutoSize

Write-Host ""
Write-Host "==== DAY31 QUICK CHECK (state vs raw.today) ====" -ForegroundColor Yellow

foreach($r in $rows){
  $dbVsState = if(
    (To-Int $r.today_events)     -ne (To-Int $r.state_events) -or
    (To-Int $r.today_quiz)       -ne (To-Int $r.state_quiz) -or
    (To-Int $r.today_wrong)      -ne (To-Int $r.state_wrong) -or
    (To-Int $r.today_wrong_done) -ne (To-Int $r.state_wrongDone)
  ){ "CHECK_NEEDED" } else { "OKISH" }

  Write-Host ("user={0} tag={1} db_vs_state={2} level={3} reason={4} action={5}" -f `
    $r.userId, $r.tag, $dbVsState, $r.coach_level, $r.coach_reason, $r.coach_action)
}

Write-Host ""
Write-Host "==== DAY31 ASSERTIONS ====" -ForegroundColor Yellow

$failed = $false
$warned = $false

$blank    = $rows | Where-Object { $_.tag -eq "blank" } | Select-Object -First 1
$comeback = $rows | Where-Object { $_.tag -eq "comeback" } | Select-Object -First 1
$steady   = $rows | Where-Object { $_.tag -eq "steady" } | Select-Object -First 1
$wrongH   = $rows | Where-Object { $_.tag -eq "wrongheavy" } | Select-Object -First 1
$recovery = $rows | Where-Object { $_.tag -eq "recovery" } | Select-Object -First 1
$anomaly  = $rows | Where-Object { $_.tag -eq "anomaly" } | Select-Object -First 1

foreach($r in $rows){
  $daysSince = To-Int $r.coach_daysSince

  switch ($r.tag) {
    "blank" {
      if((To-Int $r.today_events) -ne 0){
        Write-Host "[FAIL] blank today_events should be 0 but was $($r.today_events)" -ForegroundColor Red
        $failed = $true
      } else {
        Write-Host "[OK]   blank today_events = 0" -ForegroundColor Green
      }

      if($daysSince -ne 999){
        Write-Host "[FAIL] blank coach_daysSince should be 999 but was $daysSince" -ForegroundColor Red
        $failed = $true
      } else {
        Write-Host "[OK]   blank coach_daysSince = 999" -ForegroundColor Green
      }
    }

    "anomaly" {
      if((To-Int $r.today_quiz) -ne 0){
        Write-Host "[FAIL] anomaly today_quiz should be 0 but was $($r.today_quiz)" -ForegroundColor Red
        $failed = $true
      } else {
        Write-Host "[OK]   anomaly today_quiz = 0" -ForegroundColor Green
      }

      if((To-Int $r.today_opens) -lt 3){
        Write-Host "[WARN] anomaly today_opens expected >= 3 but was $($r.today_opens)" -ForegroundColor Yellow
        $warned = $true
      } else {
        Write-Host "[OK]   anomaly today_opens >= 3" -ForegroundColor Green
      }
    }

    default {
      if($daysSince -ne 0){
        Write-Host "[FAIL] user=$($r.userId) tag=$($r.tag) coach_daysSince should be 0 but was $daysSince" -ForegroundColor Red
        $failed = $true
      } else {
        Write-Host "[OK]   user=$($r.userId) tag=$($r.tag) coach_daysSince = 0" -ForegroundColor Green
      }

      if((To-Int $r.today_events) -ne (To-Int $r.state_events)){
        Write-Host "[WARN] user=$($r.userId) tag=$($r.tag) today events != state events ($($r.today_events) != $($r.state_events))" -ForegroundColor Yellow
        $warned = $true
      }

      if((To-Int $r.today_quiz) -ne (To-Int $r.state_quiz)){
        Write-Host "[WARN] user=$($r.userId) tag=$($r.tag) today quiz != state quiz ($($r.today_quiz) != $($r.state_quiz))" -ForegroundColor Yellow
        $warned = $true
      }

      if((To-Int $r.today_wrong) -ne (To-Int $r.state_wrong)){
        Write-Host "[WARN] user=$($r.userId) tag=$($r.tag) today wrong != state wrong ($($r.today_wrong) != $($r.state_wrong))" -ForegroundColor Yellow
        $warned = $true
      }

      if((To-Int $r.today_wrong_done) -ne (To-Int $r.state_wrongDone)){
        Write-Host "[WARN] user=$($r.userId) tag=$($r.tag) today wrong_done != state wrongDone ($($r.today_wrong_done) != $($r.state_wrongDone))" -ForegroundColor Yellow
        $warned = $true
      }
    }
  }
}

if($blank -and $comeback){
  if(Same-Decision $blank.coach_level $blank.coach_reason $blank.coach_action $comeback.coach_level $comeback.coach_reason $comeback.coach_action){
    Write-Host "[WARN] blank and comeback are identical" -ForegroundColor Yellow
    $warned = $true
  } else {
    Write-Host "[OK]   blank and comeback are separated" -ForegroundColor Green
  }
}

if($comeback -and $steady){
  if((To-Int $steady.coach_streak) -lt (To-Int $comeback.coach_streak)){
    Write-Host "[FAIL] steady streak < comeback streak ($($steady.coach_streak) < $($comeback.coach_streak))" -ForegroundColor Red
    $failed = $true
  } else {
    Write-Host "[OK]   steady streak >= comeback streak" -ForegroundColor Green
  }

  if((To-Int $steady.total_events) -le (To-Int $comeback.total_events)){
    Write-Host "[WARN] steady total_events <= comeback total_events ($($steady.total_events) <= $($comeback.total_events))" -ForegroundColor Yellow
    $warned = $true
  } else {
    Write-Host "[OK]   steady total_events > comeback total_events" -ForegroundColor Green
  }
}

if($wrongH -and $recovery){
  if((To-Int $wrongH.today_wrong) -le (To-Int $recovery.today_wrong)){
    Write-Host "[WARN] wrongheavy today_wrong <= recovery today_wrong ($($wrongH.today_wrong) <= $($recovery.today_wrong))" -ForegroundColor Yellow
    $warned = $true
  } else {
    Write-Host "[OK]   wrongheavy today_wrong > recovery today_wrong" -ForegroundColor Green
  }

  if((To-Int $recovery.today_wrong_done) -le (To-Int $wrongH.today_wrong_done)){
    Write-Host "[WARN] recovery today_wrong_done <= wrongheavy today_wrong_done ($($recovery.today_wrong_done) <= $($wrongH.today_wrong_done))" -ForegroundColor Yellow
    $warned = $true
  } else {
    Write-Host "[OK]   recovery today_wrong_done > wrongheavy today_wrong_done" -ForegroundColor Green
  }

  if(Same-Decision $wrongH.coach_level $wrongH.coach_reason $wrongH.coach_action $recovery.coach_level $recovery.coach_reason $recovery.coach_action){
    Write-Host "[WARN] wrongheavy and recovery are identical" -ForegroundColor Yellow
    $warned = $true
  } else {
    Write-Host "[OK]   wrongheavy and recovery are separated" -ForegroundColor Green
  }
}

Write-Host ""

if($failed){
  Write-Host "[FAIL] verify-day31 completed with assertion failures." -ForegroundColor Red
  exit 1
}

if($warned){
  Write-Host "[WARN] verify-day31 completed with warnings." -ForegroundColor Yellow
  exit 0
}

Write-Host "[OK] verify-day31 completed with no failures." -ForegroundColor Green
exit 0