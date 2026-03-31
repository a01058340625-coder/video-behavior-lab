param(
  [string]$artifactsDir = "C:\dev\loosegoose\goosage-scripts\core\artifacts",
  [long[]]$userIds = @(5, 9, 6, 1, 3, 10)
)

chcp 65001 > $null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$tagMap = [ordered]@{
  ([long]5)  = "collapse"
  ([long]9)  = "restart"
  ([long]6)  = "stable"
  ([long]1)  = "maintain"
  ([long]3)  = "openonly"
  ([long]10) = "recoverysafe"
}

function Safe-Get($obj,[string]$path){
  $cur = $obj
  foreach($p in ($path -split "\.")){
    if($null -eq $cur){ return $null }
    if($cur.PSObject.Properties.Name -contains $p){
      $cur = $cur.$p
    } else {
      return $null
    }
  }
  return $cur
}

function Pick-Latest([System.IO.FileInfo[]]$files,[string]$tag,[long]$uid){
  $matched = @(
    $files |
    Where-Object { $_.Name -match "^coach\.day38\.(collapse|restart|stable|maintain|openonly|recoverysafe)\.user\d+\.\d{8}-\d{9}\.json$" } |
    Where-Object { $_.Name -match ("^coach\.day38\.{0}\.user{1}\.\d{{8}}-\d{{9}}\.json$" -f [regex]::Escape($tag), $uid) } |
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

$files = @(
  Get-ChildItem $artifactsDir -File -Filter "*.json" |
  Where-Object { $_.Name -match "^coach\.day38\.(collapse|restart|stable|maintain|openonly|recoverysafe)\.user\d+\.\d{8}-\d{9}\.json$" }
)

$rows = @()

foreach($uid in $userIds){
  if(-not $tagMap.Contains([long]$uid)){ continue }

  $tag = [string]$tagMap[[long]$uid]
  $file = Pick-Latest $files $tag ([long]$uid)
  if($null -eq $file){ continue }

  $obj = Load-JsonFile $file

  $expectedLevel  = Safe-Get $obj "expected.level"
  $expectedReason = Safe-Get $obj "expected.reason"
  $expectedAction = Safe-Get $obj "expected.action"

  $actualLevel  = Safe-Get $obj "coach.prediction.level"
  $actualReason = Safe-Get $obj "coach.prediction.reasonCode"
  $actualAction = Safe-Get $obj "coach.nextAction"

  $levelHit  = ($expectedLevel  -eq $actualLevel)
  $reasonHit = ($expectedReason -eq $actualReason)
  $actionHit = ($expectedAction -eq $actualAction)

  $score = 0
  if($levelHit){  $score += 1 }
  if($reasonHit){ $score += 1 }
  if($actionHit){ $score += 1 }

  $rows += [pscustomobject]@{
    userId = [long]$uid
    tag = $tag

    expected_level  = $expectedLevel
    actual_level    = $actualLevel
    level_hit       = $levelHit

    expected_reason = $expectedReason
    actual_reason   = $actualReason
    reason_hit      = $reasonHit

    expected_action = $expectedAction
    actual_action   = $actualAction
    action_hit      = $actionHit

    accuracy_score  = $score
    total_events    = Safe-Get $obj "raw.total.total_events"
    today_events    = Safe-Get $obj "raw.today.total_events"
    today_wrong     = Safe-Get $obj "raw.today.wrong"
    today_wrong_done= Safe-Get $obj "raw.today.wrong_done"
    coach_daysSince = Safe-Get $obj "coach.prediction.evidence.daysSinceLastEvent"
    coach_streak    = Safe-Get $obj "coach.prediction.evidence.streakDays"
  }
}

if($rows.Length -eq 0){
  Write-Host ""
  Write-Host "[FAIL] No valid day38 data found." -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "==== DAY38 HABIT MAINTENANCE ACCURACY SUMMARY ====" -ForegroundColor Cyan
$rows | Select-Object `
  userId, tag,
  expected_level, actual_level, level_hit,
  expected_reason, actual_reason, reason_hit,
  expected_action, actual_action, action_hit,
  accuracy_score,
  total_events, today_events, today_wrong, today_wrong_done,
  coach_daysSince, coach_streak |
  Format-Table -AutoSize

Write-Host ""
Write-Host "==== DAY38 ASSERTIONS ====" -ForegroundColor Yellow

$failed = $false
$warned = $false

$sumScore = 0
foreach($r in $rows){
  $sumScore += (To-Int $r.accuracy_score)

  if((To-Int $r.accuracy_score) -eq 3){
    Write-Host "[OK]   user=$($r.userId) tag=$($r.tag) accuracy=3/3" -ForegroundColor Green
  }
  elseif((To-Int $r.accuracy_score) -eq 2){
    Write-Host "[WARN] user=$($r.userId) tag=$($r.tag) accuracy=2/3" -ForegroundColor Yellow
    $warned = $true
  }
  else {
    Write-Host "[FAIL] user=$($r.userId) tag=$($r.tag) accuracy=$($r.accuracy_score)/3" -ForegroundColor Red
    $failed = $true
  }
}

$maxScore = $rows.Count * 3
$avg = if($rows.Count -gt 0){ [math]::Round($sumScore / $rows.Count, 2) } else { 0 }

Write-Host ""
Write-Host ("[INFO] total_score = {0}/{1}" -f $sumScore, $maxScore) -ForegroundColor Cyan
Write-Host ("[INFO] avg_score   = {0}" -f $avg) -ForegroundColor Cyan

if($avg -lt 2.5){
  Write-Host "[FAIL] average accuracy score < 2.5" -ForegroundColor Red
  $failed = $true
} else {
  Write-Host "[OK]   average accuracy score >= 2.5" -ForegroundColor Green
}

Write-Host ""

if($failed){
  Write-Host "[FAIL] verify-day38 completed with assertion failures." -ForegroundColor Red
  exit 1
}

if($warned){
  Write-Host "[WARN] verify-day38 completed with warnings." -ForegroundColor Yellow
  exit 0
}

Write-Host "[OK] verify-day38 completed with no failures." -ForegroundColor Green
exit 0