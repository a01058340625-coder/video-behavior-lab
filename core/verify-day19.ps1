param(
  [string]$artifactsDir = "C:\dev\loosegoose\goosage-scripts\core\artifacts"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

$files = Get-ChildItem $artifactsDir -File -Filter "*.json" |
  Where-Object { $_.Name -match "coach\.day19\.s\d+\.user\d+\." } |
  Sort-Object LastWriteTime

if(-not $files){
  throw "No day19 files"
}

$rows = @()

foreach($f in $files){
  if($f.Name -match "s(\d+)\.user(\d+)"){
    $step = [int]$Matches[1]
    $uid  = [long]$Matches[2]

    $obj = Get-Content $f.FullName -Raw -Encoding utf8 | ConvertFrom-Json

    $level     = Safe-Get $obj "prediction.level"
    $reason    = Safe-Get $obj "prediction.reasonCode"
    $next      = Safe-Get $obj "nextAction"
    $events    = Safe-Get $obj "state.eventsCount"
    $quiz      = Safe-Get $obj "state.quizSubmits"
    $recent3d  = Safe-Get $obj "prediction.evidence.recentEventCount3d"
    $daysLast  = Safe-Get $obj "prediction.evidence.daysSinceLastEvent"

    if(-not $level){ $level = "NULL" }
    if(-not $reason){ $reason = "NULL" }
    if(-not $next){ $next = "NULL" }
    if($null -eq $events){ $events = -1 }
    if($null -eq $quiz){ $quiz = -1 }
    if($null -eq $recent3d){ $recent3d = -1 }
    if($null -eq $daysLast){ $daysLast = -1 }

    $rows += [pscustomobject]@{
      userId      = $uid
      step        = $step
      level       = $level
      reason      = $reason
      nextAction  = $next
      eventsCount = [int]$events
      quizSubmits = [int]$quiz
      recent3d    = [int]$recent3d
      daysLast    = [int]$daysLast
      file        = $f.Name
    }
  }
}

$rows |
  Sort-Object userId, step |
  Format-Table userId, step, level, reason, nextAction, eventsCount, quizSubmits, recent3d, daysLast -AutoSize

Write-Host ""
Write-Host "[OK] DAY19 VERIFY DONE" -ForegroundColor Green