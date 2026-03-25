param(
  [string]$artifactsDir = "C:\dev\loosegoose\goosage-scripts\core\artifacts",
  [long[]]$userIds = @(5, 9, 10, 12, 13, 14)
)

chcp 65001 > $null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$tagMap = @{}
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
    if($null -ne $v){
      return $v
    }
  }
  return $null
}

function Pick-Latest([System.IO.FileInfo[]]$files,[string]$tag,[long]$uid){
  $matched = @(
    $files |
    Where-Object { $_.Name -match ("^coach\.day30\.{0}\.user{1}\.\d{{8}}-\d{{9}}\.json$" -f [regex]::Escape($tag), $uid) } |
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
  Where-Object { $_.Name -match "^coach\.day30\.(blank|comeback|steady|wrongheavy|recovery|anomaly)\.user\d+\.\d{8}-\d{9}\.json$" }
)

$rows = @()

foreach($uid in $userIds){

  if(-not $tagMap.ContainsKey([long]$uid)){ continue }

  $tag  = [string]$tagMap[[long]$uid]
  $file = Pick-Latest $files $tag ([long]$uid)
  if($null -eq $file){ continue }

  $obj = Load-JsonFile $file

  $rows += [pscustomobject]@{
    userId = [long]$uid
    tag = $tag

    total_events = Safe-Get $obj "raw.total_events"
    opens        = Safe-Get $obj "raw.opens"
    quiz         = Safe-Get $obj "raw.quiz"
    wrong        = Safe-Get $obj "raw.wrong"
    wrong_done   = Safe-Get $obj "raw.wrong_done"
    active_days  = Safe-Get $obj "raw.active_days"
    first_day    = Safe-Get $obj "raw.first_day"
    last_day     = Safe-Get $obj "raw.last_day"

    open_ratio   = Safe-Get $obj "ratio.open_ratio"
    quiz_ratio   = Safe-Get $obj "ratio.quiz_ratio"
    wrong_ratio  = Safe-Get $obj "ratio.wrong_ratio"
    done_ratio   = Safe-Get $obj "ratio.done_ratio"

    coach_level  = Safe-Get $obj "coach.prediction.level"
    coach_reason = Safe-Get $obj "coach.prediction.reasonCode"
    coach_action = Safe-Get $obj "coach.nextAction"

    coach_events3d  = Safe-Get $obj "coach.prediction.evidence.recentEventCount3d"
    coach_daysSince = Safe-Get $obj "coach.prediction.evidence.daysSinceLastEvent"
    coach_streak    = Safe-Get $obj "coach.prediction.evidence.streakDays"

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
  Write-Host "[FAIL] No valid day30 data found." -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "==== DAY30 ENGINE STABILITY SUMMARY ====" -ForegroundColor Cyan
$rows | Select-Object `
  userId, tag,
  total_events, opens, quiz, wrong, wrong_done, active_days,
  open_ratio, quiz_ratio, wrong_ratio, done_ratio,
  coach_events3d, coach_daysSince, coach_streak,
  state_events, state_quiz, state_wrong, state_wrongDone,
  coach_level, coach_reason, coach_action |
  Format-Table -AutoSize

Write-Host ""
Write-Host "==== DAY30 DATE RANGE CHECK ====" -ForegroundColor Cyan
$rows | Select-Object `
  userId, tag,
  first_day, last_day |
  Format-Table -AutoSize

Write-Host ""
Write-Host "==== DAY30 QUICK CHECK ====" -ForegroundColor Yellow

foreach($r in $rows){
  $dbVsState = if(
  (To-Int $r.quiz) -ne (To-Int $r.state_quiz) -or
  (To-Int $r.wrong) -ne (To-Int $r.state_wrong) -or
  (To-Int $r.wrong_done) -ne (To-Int $r.state_wrongDone)
){ "CHECK_NEEDED" } else { "OKISH" }

  Write-Host ("user={0} tag={1} db_vs_state={2} level={3} action={4}" -f `
    $r.userId, $r.tag, $dbVsState, $r.coach_level, $r.coach_action)
}

Write-Host ""
Write-Host "==== DAY30 ASSERTIONS ====" -ForegroundColor Yellow

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

  if($r.tag -eq "blank"){
    if((To-Int $r.total_events) -ne 0){
      Write-Host "[FAIL] blank total_events should be 0 but was $($r.total_events)" -ForegroundColor Red
      $failed = $true
    } else {
      Write-Host "[OK]   blank total_events = 0" -ForegroundColor Green
    }
  }
  else {
    if($daysSince -ne 0){
      Write-Host "[FAIL] user=$($r.userId) tag=$($r.tag) coach_daysSince should be 0 but was $daysSince" -ForegroundColor Red
      $failed = $true
    } else {
      Write-Host "[OK]   user=$($r.userId) tag=$($r.tag) coach_daysSince = 0" -ForegroundColor Green
    }
  }

  if((To-Int $r.quiz) -ne (To-Int $r.state_quiz)){
    Write-Host "[WARN] user=$($r.userId) tag=$($r.tag) db quiz != state quiz ($($r.quiz) != $($r.state_quiz))" -ForegroundColor Yellow
    $warned = $true
  }

  if((To-Int $r.wrong) -ne (To-Int $r.state_wrong)){
  Write-Host "[WARN] user=$($r.userId) tag=$($r.tag) db wrong != state wrong ($($r.wrong) != $($r.state_wrong))" -ForegroundColor Yellow
  $warned = $true
}

if((To-Int $r.wrong_done) -ne (To-Int $r.state_wrongDone)){
  Write-Host "[WARN] user=$($r.userId) tag=$($r.tag) db wrong_done != state wrongDone ($($r.wrong_done) != $($r.state_wrongDone))" -ForegroundColor Yellow
  $warned = $true
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

  if((To-Int $steady.quiz) -le (To-Int $comeback.quiz)){
    Write-Host "[WARN] steady quiz <= comeback quiz ($($steady.quiz) <= $($comeback.quiz))" -ForegroundColor Yellow
    $warned = $true
  } else {
    Write-Host "[OK]   steady quiz > comeback quiz" -ForegroundColor Green
  }
}

if($wrongH -and $recovery){
  if((To-Int $recovery.wrong_done) -le (To-Int $wrongH.wrong_done)){
    Write-Host "[WARN] recovery wrong_done <= wrongheavy wrong_done ($($recovery.wrong_done) <= $($wrongH.wrong_done))" -ForegroundColor Yellow
    $warned = $true
  } else {
    Write-Host "[OK]   recovery wrong_done > wrongheavy wrong_done" -ForegroundColor Green
  }

  if(Same-Decision $wrongH.coach_level $wrongH.coach_reason $wrongH.coach_action $recovery.coach_level $recovery.coach_reason $recovery.coach_action){
    Write-Host "[WARN] wrongheavy and recovery are identical" -ForegroundColor Yellow
    $warned = $true
  } else {
    Write-Host "[OK]   wrongheavy and recovery are separated" -ForegroundColor Green
  }
}

if($anomaly){
  if((To-Double $anomaly.open_ratio) -lt 0.80){
    Write-Host "[FAIL] anomaly open_ratio should be >= 0.80 but was $($anomaly.open_ratio)" -ForegroundColor Red
    $failed = $true
  } else {
    Write-Host "[OK]   anomaly open_ratio >= 0.80" -ForegroundColor Green
  }

  if((To-Int $anomaly.quiz) -ne 0){
    Write-Host "[FAIL] anomaly quiz should be 0 but was $($anomaly.quiz)" -ForegroundColor Red
    $failed = $true
  } else {
    Write-Host "[OK]   anomaly quiz = 0" -ForegroundColor Green
  }
}

Write-Host ""

if($failed){
  Write-Host "[FAIL] verify-day30 completed with assertion failures." -ForegroundColor Red
  exit 1
}

if($warned){
  Write-Host "[WARN] verify-day30 completed with warnings." -ForegroundColor Yellow
  exit 0
}

Write-Host "[OK] verify-day30 completed with no failures." -ForegroundColor Green
exit 0