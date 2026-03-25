param(
  [string]$artifactsDir = "C:\dev\loosegoose\goosage-scripts\core\artifacts"
)

chcp 65001 > $null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$phaseNames = @(
  "spamopen",
  "quizonly",
  "wrongheavy",
  "recoverybias",
  "balanced",
  "lowqualitymix"
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
      $_.Name -match ("^coach\.day29\.{0}\.user{1}\.\d{{8}}-\d{{9}}\.json$" -f [regex]::Escape($tag), $uid)
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

function To-Double($v,[double]$default=0.0){
  if($null -eq $v){ return $default }
  try { return [double]$v } catch { return $default }
}

function Guess-Pattern([double]$open,[double]$quiz,[double]$wrong,[double]$done){
  if($open -ge 0.80){ return "SPAM_OPEN" }
  elseif($quiz -ge 0.75){ return "QUIZ_ONLY" }
  elseif($wrong -ge 0.45){ return "WRONG_HEAVY" }
  elseif($done -ge 0.45){ return "RECOVERY_BIAS" }
  elseif($open -ge 0.55 -and $quiz -le 0.20){ return "LOW_QUALITY_MIX" }
  elseif($open -le 0.40 -and $quiz -ge 0.20 -and $wrong -ge 0.10 -and $done -ge 0.10){
    return "BALANCED_OR_MIXED"
  }
  else {
    return "MIXED"
  }
}

function Same-Decision($aLevel,$aReason,$aAction,$bLevel,$bReason,$bAction){
  return (
    $aLevel  -eq $bLevel  -and
    $aReason -eq $bReason -and
    $aAction -eq $bAction
  )
}

function Add-PhaseFields([hashtable]$h,[string]$phase,$obj){
  $coach = Safe-Get $obj "coach"
  $raw   = Safe-Get $obj "raw"
  $ratio = Safe-Get $obj "ratio"

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

  $h["${phase}_open_ratio"]     = Safe-Get $ratio "open_ratio"
  $h["${phase}_quiz_ratio"]     = Safe-Get $ratio "quiz_ratio"
  $h["${phase}_wrong_ratio"]    = Safe-Get $ratio "wrong_ratio"
  $h["${phase}_done_ratio"]     = Safe-Get $ratio "done_ratio"
}

if(-not (Test-Path $artifactsDir)){
  Write-Host ""
  Write-Host "[FAIL] artifactsDir not found: $artifactsDir" -ForegroundColor Red
  exit 1
}

$files = @(
  Get-ChildItem $artifactsDir -File -Filter "*.json" |
  Where-Object {
    $_.Name -match ("^coach\.day29\.({0})\.user\d+\.\d{{8}}-\d{{9}}\.json$" -f $phaseRegex)
  }
)

if($files.Length -eq 0){
  Write-Host ""
  Write-Host "[FAIL] No day29 artifact files found." -ForegroundColor Red
  exit 1
}

$userIds = @(
  $files |
  ForEach-Object {
    if($_.Name -match ("^coach\.day29\.({0})\.user(\d+)\.\d{{8}}-\d{{9}}\.json$" -f $phaseRegex)){
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
  Write-Host "[FAIL] No valid day29 artifact sets found." -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "==== DAY29 LEVEL / REASON / ACTION ====" -ForegroundColor Cyan
$rows | Select-Object `
  userId,
  spamopen_Level, quizonly_Level, wrongheavy_Level, recoverybias_Level, balanced_Level, lowqualitymix_Level,
  spamopen_Reason, quizonly_Reason, wrongheavy_Reason, recoverybias_Reason, balanced_Reason, lowqualitymix_Reason,
  spamopen_Action, quizonly_Action, wrongheavy_Action, recoverybias_Action, balanced_Action, lowqualitymix_Action |
  Format-Table -AutoSize

Write-Host ""
Write-Host "==== DAY29 RAW / RATIO ====" -ForegroundColor Cyan
$rows | Select-Object `
  userId,
  spamopen_raw_total, spamopen_raw_opens, spamopen_open_ratio,
  quizonly_raw_total, quizonly_raw_quiz, quizonly_quiz_ratio,
  wrongheavy_raw_total, wrongheavy_raw_wrong, wrongheavy_wrong_ratio,
  recoverybias_raw_total, recoverybias_raw_wrongDone, recoverybias_done_ratio,
  balanced_raw_total,
  lowqualitymix_raw_total, lowqualitymix_raw_opens, lowqualitymix_open_ratio, lowqualitymix_quiz_ratio |
  Format-Table -AutoSize

Write-Host ""
Write-Host "==== DAY29 EVIDENCE / STATE ====" -ForegroundColor Cyan
$rows | Select-Object `
  userId,
  spamopen_recent3d, quizonly_recent3d, wrongheavy_recent3d, recoverybias_recent3d, balanced_recent3d, lowqualitymix_recent3d,
  spamopen_streak, quizonly_streak, wrongheavy_streak, recoverybias_streak, balanced_streak, lowqualitymix_streak,
  spamopen_events, quizonly_events, wrongheavy_events, recoverybias_events, balanced_events, lowqualitymix_events,
  spamopen_quiz, quizonly_quiz, wrongheavy_quiz, recoverybias_quiz, balanced_quiz, lowqualitymix_quiz,
  spamopen_wrong, quizonly_wrong, wrongheavy_wrong, recoverybias_wrong, balanced_wrong, lowqualitymix_wrong,
  spamopen_wrongDone, quizonly_wrongDone, wrongheavy_wrongDone, recoverybias_wrongDone, balanced_wrongDone, lowqualitymix_wrongDone |
  Format-List

Write-Host ""
Write-Host "==== DAY29 QUICK CHECK ====" -ForegroundColor Yellow

foreach($r in $rows){
  $spamVsQuiz = if(
    Same-Decision `
      $r.spamopen_Level $r.spamopen_Reason $r.spamopen_Action `
      $r.quizonly_Level $r.quizonly_Reason $r.quizonly_Action
  ){ "SAME" } else { "DIFF" }

  $wrongVsRecovery = if(
    Same-Decision `
      $r.wrongheavy_Level $r.wrongheavy_Reason $r.wrongheavy_Action `
      $r.recoverybias_Level $r.recoverybias_Reason $r.recoverybias_Action
  ){ "SAME" } else { "DIFF" }

  $balancedVsLow = if(
    Same-Decision `
      $r.balanced_Level $r.balanced_Reason $r.balanced_Action `
      $r.lowqualitymix_Level $r.lowqualitymix_Reason $r.lowqualitymix_Action
  ){ "SAME" } else { "DIFF" }

  Write-Host ("user={0}  spam_vs_quiz={1}  wrong_vs_recovery={2}  balanced_vs_lowquality={3}" -f `
    $r.userId, $spamVsQuiz, $wrongVsRecovery, $balancedVsLow)
}

Write-Host ""
Write-Host "==== DAY29 PATTERN GUESS ====" -ForegroundColor Cyan

foreach($r in $rows){
  $spamGuess = Guess-Pattern `
    (To-Double $r.spamopen_open_ratio) `
    (To-Double $r.spamopen_quiz_ratio) `
    (To-Double $r.spamopen_wrong_ratio) `
    (To-Double $r.spamopen_done_ratio)

  $quizGuess = Guess-Pattern `
    (To-Double $r.quizonly_open_ratio) `
    (To-Double $r.quizonly_quiz_ratio) `
    (To-Double $r.quizonly_wrong_ratio) `
    (To-Double $r.quizonly_done_ratio)

  $wrongGuess = Guess-Pattern `
    (To-Double $r.wrongheavy_open_ratio) `
    (To-Double $r.wrongheavy_quiz_ratio) `
    (To-Double $r.wrongheavy_wrong_ratio) `
    (To-Double $r.wrongheavy_done_ratio)

  $recoveryGuess = Guess-Pattern `
    (To-Double $r.recoverybias_open_ratio) `
    (To-Double $r.recoverybias_quiz_ratio) `
    (To-Double $r.recoverybias_wrong_ratio) `
    (To-Double $r.recoverybias_done_ratio)

  $balancedGuess = Guess-Pattern `
    (To-Double $r.balanced_open_ratio) `
    (To-Double $r.balanced_quiz_ratio) `
    (To-Double $r.balanced_wrong_ratio) `
    (To-Double $r.balanced_done_ratio)

  $lowGuess = Guess-Pattern `
    (To-Double $r.lowqualitymix_open_ratio) `
    (To-Double $r.lowqualitymix_quiz_ratio) `
    (To-Double $r.lowqualitymix_wrong_ratio) `
    (To-Double $r.lowqualitymix_done_ratio)

  Write-Host ("user={0}  spam={1}  quiz={2}  wrong={3}  recovery={4}  balanced={5}  low={6}" -f `
    $r.userId, $spamGuess, $quizGuess, $wrongGuess, $recoveryGuess, $balancedGuess, $lowGuess)
}

Write-Host ""
Write-Host "==== DAY29 ASSERTIONS ====" -ForegroundColor Yellow

$failed = $false
$warned = $false

foreach($r in $rows){

  $uid = $r.userId

  $spamGuess = Guess-Pattern `
    (To-Double $r.spamopen_open_ratio) `
    (To-Double $r.spamopen_quiz_ratio) `
    (To-Double $r.spamopen_wrong_ratio) `
    (To-Double $r.spamopen_done_ratio)

  $quizGuess = Guess-Pattern `
    (To-Double $r.quizonly_open_ratio) `
    (To-Double $r.quizonly_quiz_ratio) `
    (To-Double $r.quizonly_wrong_ratio) `
    (To-Double $r.quizonly_done_ratio)

  $wrongGuess = Guess-Pattern `
    (To-Double $r.wrongheavy_open_ratio) `
    (To-Double $r.wrongheavy_quiz_ratio) `
    (To-Double $r.wrongheavy_wrong_ratio) `
    (To-Double $r.wrongheavy_done_ratio)

  $recoveryGuess = Guess-Pattern `
    (To-Double $r.recoverybias_open_ratio) `
    (To-Double $r.recoverybias_quiz_ratio) `
    (To-Double $r.recoverybias_wrong_ratio) `
    (To-Double $r.recoverybias_done_ratio)

  $balancedGuess = Guess-Pattern `
    (To-Double $r.balanced_open_ratio) `
    (To-Double $r.balanced_quiz_ratio) `
    (To-Double $r.balanced_wrong_ratio) `
    (To-Double $r.balanced_done_ratio)

  $lowGuess = Guess-Pattern `
    (To-Double $r.lowqualitymix_open_ratio) `
    (To-Double $r.lowqualitymix_quiz_ratio) `
    (To-Double $r.lowqualitymix_wrong_ratio) `
    (To-Double $r.lowqualitymix_done_ratio)

  if($spamGuess -ne "SPAM_OPEN"){
    Write-Host "[FAIL] user=$uid spamopen pattern mismatch ($spamGuess)" -ForegroundColor Red
    $failed = $true
  } else {
    Write-Host "[OK]   user=$uid spamopen detected" -ForegroundColor Green
  }

  if($quizGuess -ne "QUIZ_ONLY"){
    Write-Host "[FAIL] user=$uid quizonly pattern mismatch ($quizGuess)" -ForegroundColor Red
    $failed = $true
  } else {
    Write-Host "[OK]   user=$uid quizonly detected" -ForegroundColor Green
  }

  if($wrongGuess -ne "WRONG_HEAVY"){
    Write-Host "[FAIL] user=$uid wrongheavy pattern mismatch ($wrongGuess)" -ForegroundColor Red
    $failed = $true
  } else {
    Write-Host "[OK]   user=$uid wrongheavy detected" -ForegroundColor Green
  }

  if($recoveryGuess -ne "RECOVERY_BIAS"){
    Write-Host "[FAIL] user=$uid recoverybias pattern mismatch ($recoveryGuess)" -ForegroundColor Red
    $failed = $true
  } else {
    Write-Host "[OK]   user=$uid recoverybias detected" -ForegroundColor Green
  }

  if($lowGuess -ne "LOW_QUALITY_MIX"){
    Write-Host "[FAIL] user=$uid lowqualitymix pattern mismatch ($lowGuess)" -ForegroundColor Red
    $failed = $true
  } else {
    Write-Host "[OK]   user=$uid lowqualitymix detected" -ForegroundColor Green
  }

  if($balancedGuess -notin @("BALANCED_OR_MIXED","MIXED")){
    Write-Host "[WARN] user=$uid balanced pattern looks unusual ($balancedGuess)" -ForegroundColor Yellow
    $warned = $true
  } else {
    Write-Host "[OK]   user=$uid balanced pattern acceptable ($balancedGuess)" -ForegroundColor Green
  }

  if(
    Same-Decision `
      $r.spamopen_Level $r.spamopen_Reason $r.spamopen_Action `
      $r.quizonly_Level $r.quizonly_Reason $r.quizonly_Action
  ){
    Write-Host "[WARN] user=$uid spamopen and quizonly same decision" -ForegroundColor Yellow
    $warned = $true
  } else {
    Write-Host "[OK]   user=$uid spamopen and quizonly separated" -ForegroundColor Green
  }

  if(
    Same-Decision `
      $r.wrongheavy_Level $r.wrongheavy_Reason $r.wrongheavy_Action `
      $r.recoverybias_Level $r.recoverybias_Reason $r.recoverybias_Action
  ){
    Write-Host "[WARN] user=$uid wrongheavy and recoverybias same decision" -ForegroundColor Yellow
    $warned = $true
  } else {
    Write-Host "[OK]   user=$uid wrongheavy and recoverybias separated" -ForegroundColor Green
  }

  if(
    Same-Decision `
      $r.balanced_Level $r.balanced_Reason $r.balanced_Action `
      $r.lowqualitymix_Level $r.lowqualitymix_Reason $r.lowqualitymix_Action
  ){
    Write-Host "[WARN] user=$uid balanced and lowqualitymix same decision" -ForegroundColor Yellow
    $warned = $true
  } else {
    Write-Host "[OK]   user=$uid balanced and lowqualitymix separated" -ForegroundColor Green
  }

  $spamDays = To-Int $r.spamopen_daysSince
  $quizDays = To-Int $r.quizonly_daysSince
  $wrongDays = To-Int $r.wrongheavy_daysSince
  $recDays = To-Int $r.recoverybias_daysSince
  $balDays = To-Int $r.balanced_daysSince
  $lowDays = To-Int $r.lowqualitymix_daysSince

  foreach($entry in @(
    @{ name="spamopen"; value=$spamDays },
    @{ name="quizonly"; value=$quizDays },
    @{ name="wrongheavy"; value=$wrongDays },
    @{ name="recoverybias"; value=$recDays },
    @{ name="balanced"; value=$balDays },
    @{ name="lowqualitymix"; value=$lowDays }
  )){
    if([int]$entry.value -ne 0){
      Write-Host ("[FAIL] user={0} {1}_daysSince should be 0 but was {2}" -f $uid,$entry.name,$entry.value) -ForegroundColor Red
      $failed = $true
    }
  }

  $spamRecent = To-Int $r.spamopen_recent3d
  $quizRecent = To-Int $r.quizonly_recent3d
  $wrongRecent = To-Int $r.wrongheavy_recent3d
  $recRecent = To-Int $r.recoverybias_recent3d
  $balRecent = To-Int $r.balanced_recent3d
  $lowRecent = To-Int $r.lowqualitymix_recent3d

  foreach($entry in @(
    @{ name="spamopen"; value=$spamRecent },
    @{ name="quizonly"; value=$quizRecent },
    @{ name="wrongheavy"; value=$wrongRecent },
    @{ name="recoverybias"; value=$recRecent },
    @{ name="balanced"; value=$balRecent },
    @{ name="lowqualitymix"; value=$lowRecent }
  )){
    if([int]$entry.value -le 0){
      Write-Host ("[WARN] user={0} {1}_recent3d <= 0 ({2})" -f $uid,$entry.name,$entry.value) -ForegroundColor Yellow
      $warned = $true
    }
  }

  $wrongDone = To-Int $r.wrongheavy_wrongDone
  $recDone = To-Int $r.recoverybias_wrongDone
  if($recDone -le $wrongDone){
    Write-Host "[WARN] user=$uid recoverybias_wrongDone <= wrongheavy_wrongDone ($recDone <= $wrongDone)" -ForegroundColor Yellow
    $warned = $true
  } else {
    Write-Host "[OK]   user=$uid recoverybias_wrongDone > wrongheavy_wrongDone" -ForegroundColor Green
  }

  $lowQuiz = To-Int $r.lowqualitymix_quiz
  $spamQuiz = To-Int $r.spamopen_quiz
  if($lowQuiz -le $spamQuiz){
    Write-Host "[OK]   user=$uid lowqualitymix quiz remains low" -ForegroundColor Green
  } else {
    Write-Host "[WARN] user=$uid lowqualitymix quiz unexpectedly high ($lowQuiz > $spamQuiz)" -ForegroundColor Yellow
    $warned = $true
  }
}

Write-Host ""

if($failed){
  Write-Host "[FAIL] verify-day29 completed with assertion failures." -ForegroundColor Red
  exit 1
}

if($warned){
  Write-Host "[WARN] verify-day29 completed with warnings." -ForegroundColor Yellow
  exit 0
}

Write-Host "[OK] verify-day29 completed with no failures." -ForegroundColor Green
exit 0