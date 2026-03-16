param(
  [string]$artifactsDir = "C:\dev\loosegoose\goosage-scripts\core\artifacts"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Safe-Get($obj,[string]$path){
  $cur=$obj
  foreach($p in ($path -split "\.")){
    if($null -eq $cur){ return $null }
    if($cur.PSObject.Properties.Name -contains $p){ $cur=$cur.$p } else { return $null }
  }
  return $cur
}

$files = Get-ChildItem $artifactsDir -File -Filter "*.json" |
  Where-Object { $_.Name -match "coach\.day25\.(baseline|phase1|phase2|phase3)\.user\d+\." } |
  Sort-Object LastWriteTime

$latest=@{}

foreach($f in $files){
  if($f.Name -match "coach\.day25\.(baseline|phase1|phase2|phase3)\.user(\d+)\."){
    $tag=$Matches[1]
    $uid=[long]$Matches[2]

    if(-not $latest.ContainsKey($uid)){ $latest[$uid]=@{} }
    $latest[$uid][$tag]=$f
  }
}

$rows=@()

foreach($uid in ($latest.Keys | Sort-Object)){

  $baselineFile = $latest[$uid]["baseline"]
  $phase1File   = $latest[$uid]["phase1"]
  $phase2File   = $latest[$uid]["phase2"]
  $phase3File   = $latest[$uid]["phase3"]

  if($baselineFile -and $phase1File -and $phase2File -and $phase3File){

    $baselineObj = Get-Content $baselineFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json
    $phase1Obj   = Get-Content $phase1File.FullName   -Raw -Encoding utf8 | ConvertFrom-Json
    $phase2Obj   = Get-Content $phase2File.FullName   -Raw -Encoding utf8 | ConvertFrom-Json
    $phase3Obj   = Get-Content $phase3File.FullName   -Raw -Encoding utf8 | ConvertFrom-Json

    $rows += [pscustomobject]@{
      userId=$uid

      baseline_Level   = Safe-Get $baselineObj "prediction.level"
      baseline_Reason  = Safe-Get $baselineObj "prediction.reasonCode"
      baseline_Action  = Safe-Get $baselineObj "nextAction"

      phase1_Level     = Safe-Get $phase1Obj "prediction.level"
      phase1_Reason    = Safe-Get $phase1Obj "prediction.reasonCode"
      phase1_Action    = Safe-Get $phase1Obj "nextAction"

      phase2_Level     = Safe-Get $phase2Obj "prediction.level"
      phase2_Reason    = Safe-Get $phase2Obj "prediction.reasonCode"
      phase2_Action    = Safe-Get $phase2Obj "nextAction"

      phase3_Level     = Safe-Get $phase3Obj "prediction.level"
      phase3_Reason    = Safe-Get $phase3Obj "prediction.reasonCode"
      phase3_Action    = Safe-Get $phase3Obj "nextAction"
    }
  }
}

$rows | Format-Table -AutoSize