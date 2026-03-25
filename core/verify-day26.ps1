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
  "sparse",
  "steady",
  "open_only",
  "quiz_only",
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
      $_.Name -match ("^coach\.day26\.{0}\.user{1}\.\d+\.json$" -f [regex]::Escape($tag), $uid)
    } |
    Sort-Object LastWriteTime -Descending
  )

  if($matched.Length -gt 0){
    return $matched[0]
  }

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

if(-not (Test-Path $artifactsDir)){
  Write-Host ""
  Write-Host "[FAIL] artifactsDir not found: $artifactsDir" -ForegroundColor Red
  exit 1
}

$files = @(
  Get-ChildItem $artifactsDir -File -Filter "*.json" |
  Where-Object {
    $_.Name -match ("^coach\.day26\.({0})\.user\d+\.\d+\.json$" -f $phaseRegex)
  }
)

if($files.Length -eq 0){
  Write-Host ""
  Write-Host "[FAIL] No day26 artifact files found." -ForegroundColor Red
  exit 1
}

$userIds = @(
  $files |
  ForEach-Object {
    if($_.Name -match ("^coach\.day26\.({0})\.user(\d+)\.\d+\.json$" -f $phaseRegex)){
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
  Write-Host "[FAIL] No valid day26 artifact sets found." -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "==== DAY26 LEVEL / REASON / ACTION ====" -ForegroundColor Cyan
$rows | Select-Object `
  userId, `
  baseline_Level, sparse_Level, steady_Level, open_only_Level, quiz_only_Level, risk_Level, recovery_Level, `
  baseline_Reason, sparse_Reason, steady_Reason, open_only_Reason, quiz_only_Reason, risk_Reason, recovery_Reason, `
  baseline_Action, sparse_Action, steady_Action, open_only_Action, quiz_only_Action, risk_Action, recovery_Action |
  Format-Table -AutoSize

Write-Host ""
Write-Host "==== DAY26 EVIDENCE ====" -ForegroundColor Cyan
$rows | Select-Object `
  userId, `
  baseline_daysSince, sparse_daysSince, steady_daysSince, open_only_daysSince, quiz_only_daysSince, risk_daysSince, recovery_daysSince, `
  baseline_recent3d, sparse_recent3d, steady_recent3d, open_only_recent3d, quiz_only_recent3d, risk_recent3d, recovery_recent3d, `
  baseline_streak, sparse_streak, steady_streak, open_only_streak, quiz_only_streak, risk_streak, recovery_streak |
  Format-List

Write-Host ""
Write-Host "==== DAY26 STATE ====" -ForegroundColor Cyan
$rows | Select-Object `
  userId, `
  baseline_events, sparse_events, steady_events, open_only_events, quiz_only_events, risk_events, recovery_events, `
  baseline_quiz, sparse_quiz, steady_quiz, open_only_quiz, quiz_only_quiz, risk_quiz, recovery_quiz, `
  baseline_wrong, sparse_wrong, steady_wrong, open_only_wrong, quiz_only_wrong, risk_wrong, recovery_wrong, `
  baseline_wrongDone, sparse_wrongDone, steady_wrongDone, open_only_wrongDone, quiz_only_wrongDone, risk_wrongDone, recovery_wrongDone |
  Format-List

Write-Host ""
Write-Host "==== DAY26 QUICK CHECK ====" -ForegroundColor Yellow

foreach($r in $rows){
  $steadyVsSparse = if(
    $r.steady_Level  -ne $r.sparse_Level  -or
    $r.steady_Reason -ne $r.sparse_Reason -or
    $r.steady_Action -ne $r.sparse_Action
  ){ "DIFF" } else { "SAME" }

  $openVsQuiz = if(
    $r.open_only_Level  -ne $r.quiz_only_Level  -or
    $r.open_only_Reason -ne $r.quiz_only_Reason -or
    $r.open_only_Action -ne $r.quiz_only_Action
  ){ "DIFF" } else { "SAME" }

  $riskVsRecovery = if(
    $r.risk_Level  -ne $r.recovery_Level  -or
    $r.risk_Reason -ne $r.recovery_Reason -or
    $r.risk_Action -ne $r.recovery_Action
  ){ "DIFF" } else { "SAME" }

  Write-Host ("user={0}  steady_vs_sparse={1}  open_vs_quiz={2}  risk_vs_recovery={3}" -f `
    $r.userId, $steadyVsSparse, $openVsQuiz, $riskVsRecovery)
}

Write-Host ""
Write-Host "[OK] verify-day26 completed." -ForegroundColor Green