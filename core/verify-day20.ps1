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
  Where-Object { $_.Name -match "coach\.day20\.close\.user\d+\." } |
  Sort-Object LastWriteTime

if(-not $files){
  throw "No day20 close files"
}

$rows = @()
foreach($f in $files){
  if($f.Name -match "user(\d+)"){
    $uid = [long]$Matches[1]
    $obj = Get-Content $f.FullName -Raw -Encoding utf8 | ConvertFrom-Json

    $level = Safe-Get $obj "prediction.level"
    if(-not $level){ $level = "NULL" }

    $reason = Safe-Get $obj "prediction.reasonCode"
    if(-not $reason){ $reason = "NULL" }

    $recent3d = Safe-Get $obj "prediction.evidence.recentEventCount3d"
    if($null -eq $recent3d){ $recent3d = Safe-Get $obj "state.recentEventCount3d" }
    if($null -eq $recent3d){ $recent3d = -1 }

    $dsl = Safe-Get $obj "prediction.evidence.daysSinceLastEvent"
    if($null -eq $dsl){ $dsl = Safe-Get $obj "state.daysSinceLastEvent" }
    if($null -eq $dsl){ $dsl = -1 }

    $rows += [pscustomobject]@{
      userId             = $uid
      level              = $level
      reason             = $reason
      recent3d           = [int]$recent3d
      daysSinceLastEvent = [int]$dsl
      file               = $f.Name
    }
  }
}

$rows | Sort-Object userId | Format-Table -AutoSize
Write-Host ""
Write-Host "[OK] DAY20 VERIFY DONE" -ForegroundColor Green