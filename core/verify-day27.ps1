param(
  [string]$artifactsDir = "C:\dev\loosegoose\goosage-scripts\core\artifacts"
)

chcp 65001 > $null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$phaseNames = @(
  "baseline",
  "comeback",
  "steady",
  "risk",
  "recovery"
)

$phaseRegex = ($phaseNames -join "|")

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
    Where-Object {
      $_.Name -match ("^coach\.day27\.{0}\.user{1}\.\d{{8}}-\d{{9}}\.json$" -f [regex]::Escape($tag), $uid)
    } |
    Sort-Object LastWriteTime -Descending
  )

  if($matched.Length -gt 0){ return $matched[0] }
  return $null
}

function Load-JsonFile([System.IO.FileInfo]$file){
  Get-Content $file.FullName -Raw -Encoding utf8 | ConvertFrom-Json
}

function Add-PhaseFields([hashtable]$h,[string]$phase,$obj){
  $h["${phase}_Level"]     = Safe-Get $obj "prediction.level"
  $h["${phase}_Reason"]    = Safe-Get $obj "prediction.reasonCode"
  $h["${phase}_Action"]    = Safe-Get $obj "nextAction"

  $h["${phase}_daysSince"] = Safe-Get $obj "prediction.evidence.daysSinceLastEvent"
  $h["${phase}_recent3d"]  = Safe-Get $obj "prediction.evidence.recentEventCount3d"
  $h["${phase}_streak"]    = Safe-Get $obj "prediction.evidence.streakDays"

  $h["${phase}_events"]    = Safe-Get $obj "state.eventsCount"
  $h["${phase}_quiz"]      = Safe-Get $obj "state.quizSubmits"
  $h["${phase}_wrong"]     = Safe-Get $obj "state.wrongReviews"
  $h["${phase}_wrongDone"] = Safe-Get-Any $obj @(
    "state.wrongReviewDone",
    "state.wrongReviewsDone"
  )
}

function Same-Decision($aLevel,$aReason,$aAction,$bLevel,$bReason,$bAction){
  return (
    $aLevel  -eq $bLevel  -and
    $aReason -eq $bReason -and
    $aAction -eq $bAction
  )
}

function To-Int($v,[int]$default=0){
  if($null -eq $v){ return $default }
  try { return [int]$v } catch { return $default }
}

if(-not (Test-Path $artifactsDir)){
  Write-Host ""
  Write-Host "[FAIL] artifactsDir not found: $artifactsDir" -ForegroundColor Red
  exit 1
}

$files = @(
  Get-ChildItem $artifactsDir -File -Filter "*.json" |
  Where-Object {
    $_.Name -match ("^coach\.day27\.({0})\.user\d+\.\d{{8}}-\d{{9}}\.json$" -f $phaseRegex)
  }
)

if($files.Length -eq 0){
  Write-Host ""
  Write-Host "[FAIL] No day27 artifact files found." -ForegroundColor Red
  exit 1
}

$userIds = @(
  $files |
  ForEach-Object {
    if($_.Name -match ("^coach\.day27\.({0})\.user(\d+)\.\d{{8}}-\d{{9}}\.json$" -f $phaseRegex)){
      [long]$Matches[2]
    }
  } |
  Sort-Object -Unique
)

$rows = @()

foreach($uid in $userIds){

  $phaseFiles = @{}
  $allFound = $true

  foreach($phase in $phaseNames){
    $f = Pick-Latest $files $phase $uid
    if($null -eq $f){
      $allFound = $false
      break
    }
    $phaseFiles[$phase] = $f
  }

  if(-not $allFound){
    continue
  }

  $objs = @{}
  foreach($phase in $phaseNames){
    $objs[$phase] = Load-JsonFile $phaseFiles[$phase]
  }

  $row = @{
    userId = $uid
  }

  foreach($phase in $phaseNames){
    Add-PhaseFields $row $phase $objs[$phase]
  }

  $rows += [pscustomobject]$row
}

if($rows.Length -eq 0){
  Write-Host ""
  Write-Host "[FAIL] No valid day27 artifact sets found." -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "==== DAY27 LEVEL / REASON / ACTION ====" -ForegroundColor Cyan
$rows | Select-Object `
  userId,
  baseline_Level, comeback_Level, steady_Level, risk_Level, recovery_Level,
  baseline_Reason, comeback_Reason, steady_Reason, risk_Reason, recovery_Reason,
  baseline_Action, comeback_Action, steady_Action, risk_Action, recovery_Action |
  Format-Table -AutoSize

Write-Host ""
Write-Host "==== DAY27 EVIDENCE ====" -ForegroundColor Cyan
$rows | Select-Object `
  userId,
  baseline_daysSince, comeback_daysSince, steady_daysSince, risk_daysSince, recovery_daysSince,
  baseline_recent3d, comeback_recent3d, steady_recent3d, risk_recent3d, recovery_recent3d,
  baseline_streak, comeback_streak, steady_streak, risk_streak, recovery_streak |
  Format-List

Write-Host ""
Write-Host "==== DAY27 STATE ====" -ForegroundColor Cyan
$rows | Select-Object `
  userId,
  baseline_events, comeback_events, steady_events, risk_events, recovery_events,
  baseline_quiz, comeback_quiz, steady_quiz, risk_quiz, recovery_quiz,
  baseline_wrong, comeback_wrong, steady_wrong, risk_wrong, recovery_wrong,
  baseline_wrongDone, comeback_wrongDone, steady_wrongDone, risk_wrongDone, recovery_wrongDone |
  Format-List

Write-Host ""
Write-Host "==== DAY27 QUICK CHECK ====" -ForegroundColor Yellow

foreach($r in $rows){
  $baselineVsComeback = if(
    Same-Decision $r.baseline_Level $r.baseline_Reason $r.baseline_Action `
                  $r.comeback_Level $r.comeback_Reason $r.comeback_Action
  ){ "SAME" } else { "DIFF" }

  $steadyVsComeback = if(
    Same-Decision $r.steady_Level $r.steady_Reason $r.steady_Action `
                  $r.comeback_Level $r.comeback_Reason $r.comeback_Action
  ){ "SAME" } else { "DIFF" }

  $riskVsRecovery = if(
    Same-Decision $r.risk_Level $r.risk_Reason $r.risk_Action `
                  $r.recovery_Level $r.recovery_Reason $r.recovery_Action
  ){ "SAME" } else { "DIFF" }

  Write-Host ("user={0}  baseline_vs_comeback={1}  steady_vs_comeback={2}  risk_vs_recovery={3}" -f `
    $r.userId, $baselineVsComeback, $steadyVsComeback, $riskVsRecovery)
}

Write-Host ""
Write-Host "==== DAY27 ASSERTIONS ====" -ForegroundColor Yellow

$failed = $false
$warned = $false

foreach($r in $rows){
  $uid = $r.userId

  $baselineDays  = To-Int $r.baseline_daysSince
  $comebackDays  = To-Int $r.comeback_daysSince
  $steadyDays    = To-Int $r.steady_daysSince
  $riskDays      = To-Int $r.risk_daysSince
  $recoveryDays  = To-Int $r.recovery_daysSince

  $baselineRecent = To-Int $r.baseline_recent3d
  $comebackRecent = To-Int $r.comeback_recent3d
  $steadyRecent   = To-Int $r.steady_recent3d
  $riskRecent     = To-Int $r.risk_recent3d
  $recoveryRecent = To-Int $r.recovery_recent3d

  $comebackStreak = To-Int $r.comeback_streak
  $steadyStreak   = To-Int $r.steady_streak

  $riskWrong      = To-Int $r.risk_wrong
  $recoveryWrong  = To-Int $r.recovery_wrong
  $riskWrongDone  = To-Int $r.risk_wrongDone
  $recoveryWrongDone = To-Int $r.recovery_wrongDone

  $baselineSameAsComeback = Same-Decision `
    $r.baseline_Level $r.baseline_Reason $r.baseline_Action `
    $r.comeback_Level $r.comeback_Reason $r.comeback_Action

  if($baselineSameAsComeback){
    Write-Host "[FAIL] user=$uid baseline and comeback are identical" -ForegroundColor Red
    $failed = $true
  }
  else {
    Write-Host "[OK]   user=$uid baseline and comeback are separated" -ForegroundColor Green
  }

  if($steadyRecent -lt $comebackRecent){
    Write-Host "[FAIL] user=$uid steady_recent3d < comeback_recent3d ($steadyRecent < $comebackRecent)" -ForegroundColor Red
    $failed = $true
  }
  else {
    Write-Host "[OK]   user=$uid steady_recent3d >= comeback_recent3d" -ForegroundColor Green
  }

  if($steadyStreak -lt $comebackStreak){
    Write-Host "[FAIL] user=$uid steady_streak < comeback_streak ($steadyStreak < $comebackStreak)" -ForegroundColor Red
    $failed = $true
  }
  else {
    Write-Host "[OK]   user=$uid steady_streak >= comeback_streak" -ForegroundColor Green
  }

  if($comebackDays -ne 0){
    Write-Host "[FAIL] user=$uid comeback_daysSince should be 0 but was $comebackDays" -ForegroundColor Red
    $failed = $true
  }
  else {
    Write-Host "[OK]   user=$uid comeback_daysSince = 0" -ForegroundColor Green
  }

  if($steadyDays -ne 0){
    Write-Host "[FAIL] user=$uid steady_daysSince should be 0 but was $steadyDays" -ForegroundColor Red
    $failed = $true
  }
  else {
    Write-Host "[OK]   user=$uid steady_daysSince = 0" -ForegroundColor Green
  }

  if($riskDays -ne 0){
    Write-Host "[FAIL] user=$uid risk_daysSince should be 0 but was $riskDays" -ForegroundColor Red
    $failed = $true
  }
  else {
    Write-Host "[OK]   user=$uid risk_daysSince = 0" -ForegroundColor Green
  }

  if($recoveryDays -ne 0){
    Write-Host "[FAIL] user=$uid recovery_daysSince should be 0 but was $recoveryDays" -ForegroundColor Red
    $failed = $true
  }
  else {
    Write-Host "[OK]   user=$uid recovery_daysSince = 0" -ForegroundColor Green
  }

  if($baselineDays -lt 1){
    Write-Host "[WARN] user=$uid baseline_daysSince looks lower than expected ($baselineDays)" -ForegroundColor Yellow
    $warned = $true
  }

  if($recoveryWrongDone -le $riskWrongDone){
    Write-Host "[WARN] user=$uid recovery_wrongDone <= risk_wrongDone ($recoveryWrongDone <= $riskWrongDone)" -ForegroundColor Yellow
    $warned = $true
  }
  else {
    Write-Host "[OK]   user=$uid recovery_wrongDone > risk_wrongDone" -ForegroundColor Green
  }

  if($recoveryWrongDone -eq 0){
    Write-Host "[WARN] user=$uid recovery_wrongDone = 0 (WRONG_REVIEW_DONE 집계 미반영 가능성)" -ForegroundColor Yellow
    $warned = $true
  }

  if($riskWrong -le 0){
    Write-Host "[WARN] user=$uid risk_wrong <= 0 (risk phase 오답 집계 약함)" -ForegroundColor Yellow
    $warned = $true
  }

  if($recoveryRecent -lt $riskRecent){
    Write-Host "[WARN] user=$uid recovery_recent3d < risk_recent3d ($recoveryRecent < $riskRecent)" -ForegroundColor Yellow
    $warned = $true
  }
  else {
    Write-Host "[OK]   user=$uid recovery_recent3d >= risk_recent3d" -ForegroundColor Green
  }

  if(
    Same-Decision `
      $r.risk_Level $r.risk_Reason $r.risk_Action `
      $r.recovery_Level $r.recovery_Reason $r.recovery_Action
  ){
    Write-Host "[WARN] user=$uid risk and recovery are still identical" -ForegroundColor Yellow
    $warned = $true
  }
  else {
    Write-Host "[OK]   user=$uid risk and recovery are separated" -ForegroundColor Green
  }
}

Write-Host ""

if($failed){
  Write-Host "[FAIL] verify-day27 completed with assertion failures." -ForegroundColor Red
  exit 1
}

if($warned){
  Write-Host "[WARN] verify-day27 completed with warnings." -ForegroundColor Yellow
  exit 0
}

Write-Host "[OK] verify-day27 completed with no failures." -ForegroundColor Green
exit 0