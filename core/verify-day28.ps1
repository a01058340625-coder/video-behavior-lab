param(
  [string]$artifactsDir = "C:\dev\loosegoose\goosage-scripts\core\artifacts"
)

chcp 65001 > $null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$phaseNames = @(
  "qualityA",
  "qualityB",
  "qualityC",
  "qualityD",
  "qualityE"
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
      $_.Name -match ("^coach\.day28\.{0}\.user{1}\.\d{{8}}-\d{{9}}\.json$" -f [regex]::Escape($tag), $uid)
    } |
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

function Add-PhaseFields([hashtable]$h,[string]$phase,$obj){
  $coach = Safe-Get $obj "coach"
  $raw   = Safe-Get $obj "raw"
  $exp   = Safe-Get $obj "expected"

  $h["${phase}_Level"]     = Safe-Get $coach "prediction.level"
  $h["${phase}_Reason"]    = Safe-Get $coach "prediction.reasonCode"
  $h["${phase}_Action"]    = Safe-Get $coach "nextAction"

  $h["${phase}_daysSince"] = Safe-Get $coach "prediction.evidence.daysSinceLastEvent"
  $h["${phase}_recent3d"]  = Safe-Get $coach "prediction.evidence.recentEventCount3d"
  $h["${phase}_streak"]    = Safe-Get $coach "prediction.evidence.streakDays"

  $h["${phase}_events"]    = Safe-Get $coach "state.eventsCount"
  $h["${phase}_quiz"]      = Safe-Get $coach "state.quizSubmits"
  $h["${phase}_wrong"]     = Safe-Get $coach "state.wrongReviews"
  $h["${phase}_wrongDone"] = Safe-Get-Any $coach @(
    "state.wrongReviewDone",
    "state.wrongReviewsDone"
  )

  $h["${phase}_raw_total"]      = Safe-Get $raw "total_events"
  $h["${phase}_raw_opens"]      = Safe-Get $raw "opens"
  $h["${phase}_raw_quiz"]       = Safe-Get $raw "quiz"
  $h["${phase}_raw_wrong"]      = Safe-Get $raw "wrong"
  $h["${phase}_raw_wrongDone"]  = Safe-Get $raw "wrong_done"
  $h["${phase}_raw_activeDays"] = Safe-Get $raw "active_days"

  $h["${phase}_exp_total"]      = Safe-Get $exp "total_events"
  $h["${phase}_exp_opens"]      = Safe-Get $exp "opens"
  $h["${phase}_exp_quiz"]       = Safe-Get $exp "quiz"
  $h["${phase}_exp_wrong"]      = Safe-Get $exp "wrong"
  $h["${phase}_exp_wrongDone"]  = Safe-Get $exp "wrong_done"
  $h["${phase}_exp_activeDays"] = Safe-Get $exp "active_days"
}

if(-not (Test-Path $artifactsDir)){
  Write-Host ""
  Write-Host "[FAIL] artifactsDir not found: $artifactsDir" -ForegroundColor Red
  exit 1
}

$files = @(
  Get-ChildItem $artifactsDir -File -Filter "*.json" |
  Where-Object {
    $_.Name -match ("^coach\.day28\.({0})\.user\d+\.\d{{8}}-\d{{9}}\.json$" -f $phaseRegex)
  }
)

if($files.Length -eq 0){
  Write-Host ""
  Write-Host "[FAIL] No day28 artifact files found." -ForegroundColor Red
  exit 1
}

$userIds = @(
  $files |
  ForEach-Object {
    if($_.Name -match ("^coach\.day28\.({0})\.user(\d+)\.\d{{8}}-\d{{9}}\.json$" -f $phaseRegex)){
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
  Write-Host "[FAIL] No valid day28 artifact sets found." -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "==== DAY28 LEVEL / REASON / ACTION ====" -ForegroundColor Cyan
$rows | Select-Object `
  userId,
  qualityA_Level, qualityB_Level, qualityC_Level, qualityD_Level, qualityE_Level,
  qualityA_Reason, qualityB_Reason, qualityC_Reason, qualityD_Reason, qualityE_Reason,
  qualityA_Action, qualityB_Action, qualityC_Action, qualityD_Action, qualityE_Action |
  Format-Table -AutoSize

Write-Host ""
Write-Host "==== DAY28 RAW vs EXPECTED ====" -ForegroundColor Cyan
$rows | Select-Object `
  userId,
  qualityA_raw_total, qualityA_exp_total,
  qualityB_raw_total, qualityB_exp_total,
  qualityC_raw_total, qualityC_exp_total,
  qualityD_raw_total, qualityD_exp_total,
  qualityE_raw_total, qualityE_exp_total |
  Format-Table -AutoSize

Write-Host ""
Write-Host "==== DAY28 EVIDENCE ====" -ForegroundColor Cyan
$rows | Select-Object `
  userId,
  qualityA_daysSince, qualityB_daysSince, qualityC_daysSince, qualityD_daysSince, qualityE_daysSince,
  qualityA_recent3d, qualityB_recent3d, qualityC_recent3d, qualityD_recent3d, qualityE_recent3d,
  qualityA_streak, qualityB_streak, qualityC_streak, qualityD_streak, qualityE_streak |
  Format-List

Write-Host ""
Write-Host "==== DAY28 STATE ====" -ForegroundColor Cyan
$rows | Select-Object `
  userId,
  qualityA_events, qualityB_events, qualityC_events, qualityD_events, qualityE_events,
  qualityA_quiz, qualityB_quiz, qualityC_quiz, qualityD_quiz, qualityE_quiz,
  qualityA_wrong, qualityB_wrong, qualityC_wrong, qualityD_wrong, qualityE_wrong,
  qualityA_wrongDone, qualityB_wrongDone, qualityC_wrongDone, qualityD_wrongDone, qualityE_wrongDone |
  Format-List

Write-Host ""
Write-Host "==== DAY28 ASSERTIONS ====" -ForegroundColor Yellow

$failed = $false
$warned = $false

foreach($r in $rows){
  $uid = $r.userId

  foreach($phase in $phaseNames){
    $rawTotal = To-Int $r."${phase}_raw_total"
    $expTotal = To-Int $r."${phase}_exp_total"
    $rawOpen  = To-Int $r."${phase}_raw_opens"
    $expOpen  = To-Int $r."${phase}_exp_opens"
    $rawQuiz  = To-Int $r."${phase}_raw_quiz"
    $expQuiz  = To-Int $r."${phase}_exp_quiz"
    $rawWrong = To-Int $r."${phase}_raw_wrong"
    $expWrong = To-Int $r."${phase}_exp_wrong"
    $rawDone  = To-Int $r."${phase}_raw_wrongDone"
    $expDone  = To-Int $r."${phase}_exp_wrongDone"
    $rawDays  = To-Int $r."${phase}_raw_activeDays"
    $expDays  = To-Int $r."${phase}_exp_activeDays"

    if($rawTotal -ne $expTotal -or $rawOpen -ne $expOpen -or $rawQuiz -ne $expQuiz -or $rawWrong -ne $expWrong -or $rawDone -ne $expDone -or $rawDays -ne $expDays){
      Write-Host "[FAIL] user=$uid $phase raw != expected" -ForegroundColor Red
      Write-Host ("       raw(total/open/quiz/wrong/done/days)= {0}/{1}/{2}/{3}/{4}/{5}" -f $rawTotal,$rawOpen,$rawQuiz,$rawWrong,$rawDone,$rawDays) -ForegroundColor Red
      Write-Host ("       exp(total/open/quiz/wrong/done/days)= {0}/{1}/{2}/{3}/{4}/{5}" -f $expTotal,$expOpen,$expQuiz,$expWrong,$expDone,$expDays) -ForegroundColor Red
      $failed = $true
    }
    else {
      Write-Host "[OK]   user=$uid $phase raw == expected" -ForegroundColor Green
    }
  }

  $aDays = To-Int $r.qualityA_daysSince
  $bDays = To-Int $r.qualityB_daysSince
  $cDays = To-Int $r.qualityC_daysSince
  $dDays = To-Int $r.qualityD_daysSince
  $eDays = To-Int $r.qualityE_daysSince

  $aRecent = To-Int $r.qualityA_recent3d
  $bRecent = To-Int $r.qualityB_recent3d
  $cRecent = To-Int $r.qualityC_recent3d
  $dRecent = To-Int $r.qualityD_recent3d
  $eRecent = To-Int $r.qualityE_recent3d

  $aStreak = To-Int $r.qualityA_streak
  $bStreak = To-Int $r.qualityB_streak
  $cStreak = To-Int $r.qualityC_streak
  $dStreak = To-Int $r.qualityD_streak
  $eStreak = To-Int $r.qualityE_streak

  $dDone = To-Int $r.qualityD_wrongDone
  $bDone = To-Int $r.qualityB_wrongDone
  $eQuiz = To-Int $r.qualityE_quiz

  if($aDays -ne 0){
    Write-Host "[FAIL] user=$uid qualityA_daysSince should be 0 but was $aDays" -ForegroundColor Red
    $failed = $true
  } else { Write-Host "[OK]   user=$uid qualityA_daysSince = 0" -ForegroundColor Green }

  if($bDays -ne 0){
    Write-Host "[FAIL] user=$uid qualityB_daysSince should be 0 but was $bDays" -ForegroundColor Red
    $failed = $true
  } else { Write-Host "[OK]   user=$uid qualityB_daysSince = 0" -ForegroundColor Green }

  if($dDays -ne 0){
    Write-Host "[FAIL] user=$uid qualityD_daysSince should be 0 but was $dDays" -ForegroundColor Red
    $failed = $true
  } else { Write-Host "[OK]   user=$uid qualityD_daysSince = 0" -ForegroundColor Green }

  if($eDays -ne 0){
    Write-Host "[FAIL] user=$uid qualityE_daysSince should be 0 but was $eDays" -ForegroundColor Red
    $failed = $true
  } else { Write-Host "[OK]   user=$uid qualityE_daysSince = 0" -ForegroundColor Green }

  if($cDays -lt 1){
    Write-Host "[FAIL] user=$uid qualityC_daysSince should be >= 1 but was $cDays" -ForegroundColor Red
    $failed = $true
  } else { Write-Host "[OK]   user=$uid qualityC_daysSince >= 1" -ForegroundColor Green }

  if($aStreak -lt 2){
    Write-Host "[WARN] user=$uid qualityA_streak looks lower than expected ($aStreak)" -ForegroundColor Yellow
    $warned = $true
  } else { Write-Host "[OK]   user=$uid qualityA_streak >= 2" -ForegroundColor Green }

  if($dStreak -lt 2){
    Write-Host "[WARN] user=$uid qualityD_streak looks lower than expected ($dStreak)" -ForegroundColor Yellow
    $warned = $true
  } else { Write-Host "[OK]   user=$uid qualityD_streak >= 2" -ForegroundColor Green }

  if($cRecent -gt 0){
    Write-Host "[WARN] user=$uid qualityC_recent3d > 0 ($cRecent) ; 3일 전 경계값 반영 확인 필요" -ForegroundColor Yellow
    $warned = $true
  } else { Write-Host "[OK]   user=$uid qualityC_recent3d = 0" -ForegroundColor Green }

  if($dDone -le $bDone){
    Write-Host "[WARN] user=$uid qualityD_wrongDone <= qualityB_wrongDone ($dDone <= $bDone)" -ForegroundColor Yellow
    $warned = $true
  } else { Write-Host "[OK]   user=$uid qualityD_wrongDone > qualityB_wrongDone" -ForegroundColor Green }

  if($eQuiz -ne 0){
    Write-Host "[FAIL] user=$uid qualityE_quiz should be 0 but was $eQuiz" -ForegroundColor Red
    $failed = $true
  } else { Write-Host "[OK]   user=$uid qualityE_quiz = 0" -ForegroundColor Green }

  if($aRecent -lt $eRecent){
    Write-Host "[WARN] user=$uid qualityA_recent3d < qualityE_recent3d ($aRecent < $eRecent)" -ForegroundColor Yellow
    $warned = $true
  } else { Write-Host "[OK]   user=$uid qualityA_recent3d >= qualityE_recent3d" -ForegroundColor Green }

  if($r.qualityA_Level -eq $r.qualityB_Level -and
     $r.qualityA_Reason -eq $r.qualityB_Reason -and
     $r.qualityA_Action -eq $r.qualityB_Action){
    Write-Host "[WARN] user=$uid qualityA and qualityB are identical" -ForegroundColor Yellow
    $warned = $true
  } else {
    Write-Host "[OK]   user=$uid qualityA and qualityB are separated" -ForegroundColor Green
  }

  if($r.qualityB_Level -eq $r.qualityE_Level -and
     $r.qualityB_Reason -eq $r.qualityE_Reason -and
     $r.qualityB_Action -eq $r.qualityE_Action){
    Write-Host "[WARN] user=$uid qualityB and qualityE are identical" -ForegroundColor Yellow
    $warned = $true
  } else {
    Write-Host "[OK]   user=$uid qualityB and qualityE are separated" -ForegroundColor Green
  }

  if($r.qualityD_Level -eq $r.qualityB_Level -and
     $r.qualityD_Reason -eq $r.qualityB_Reason -and
     $r.qualityD_Action -eq $r.qualityB_Action){
    Write-Host "[WARN] user=$uid qualityD and qualityB are identical" -ForegroundColor Yellow
    $warned = $true
  } else {
    Write-Host "[OK]   user=$uid qualityD and qualityB are separated" -ForegroundColor Green
  }
}

Write-Host ""

if($failed){
  Write-Host "[FAIL] verify-day28 completed with assertion failures." -ForegroundColor Red
  exit 1
}

if($warned){
  Write-Host "[WARN] verify-day28 completed with warnings." -ForegroundColor Yellow
  exit 0
}

Write-Host "[OK] verify-day28 completed with no failures." -ForegroundColor Green
exit 0