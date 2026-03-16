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
  Where-Object { $_.Name -match "coach\.day23\.(baseline|afterMin1|afterMin2|afterMin3)\.user\d+\." } |
  Sort-Object LastWriteTime

$latest=@{}

foreach($f in $files){
  if($f.Name -match "coach\.day23\.(baseline|afterMin1|afterMin2|afterMin3)\.user(\d+)\."){
    $tag=$Matches[1]
    $uid=[long]$Matches[2]

    if(-not $latest.ContainsKey($uid)){ $latest[$uid]=@{} }
    $latest[$uid][$tag]=$f
  }
}

$rows=@()

foreach($uid in ($latest.Keys | Sort-Object)){

  $baselineFile = $latest[$uid]["baseline"]
  $min1File     = $latest[$uid]["afterMin1"]
  $min2File     = $latest[$uid]["afterMin2"]
  $min3File     = $latest[$uid]["afterMin3"]

  if($baselineFile -and $min1File -and $min2File -and $min3File){

    $baselineObj = Get-Content $baselineFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json
    $min1Obj     = Get-Content $min1File.FullName     -Raw -Encoding utf8 | ConvertFrom-Json
    $min2Obj     = Get-Content $min2File.FullName     -Raw -Encoding utf8 | ConvertFrom-Json
    $min3Obj     = Get-Content $min3File.FullName     -Raw -Encoding utf8 | ConvertFrom-Json

    $rows += [pscustomobject]@{
      userId=$uid

      baseline_Level   = Safe-Get $baselineObj "prediction.level"
      baseline_Reason  = Safe-Get $baselineObj "prediction.reasonCode"
      baseline_Action  = Safe-Get $baselineObj "nextAction"

      min1_Level       = Safe-Get $min1Obj "prediction.level"
      min1_Reason      = Safe-Get $min1Obj "prediction.reasonCode"
      min1_Action      = Safe-Get $min1Obj "nextAction"

      min2_Level       = Safe-Get $min2Obj "prediction.level"
      min2_Reason      = Safe-Get $min2Obj "prediction.reasonCode"
      min2_Action      = Safe-Get $min2Obj "nextAction"

      min3_Level       = Safe-Get $min3Obj "prediction.level"
      min3_Reason      = Safe-Get $min3Obj "prediction.reasonCode"
      min3_Action      = Safe-Get $min3Obj "nextAction"
    }
  }
}

$rows | Format-Table -AutoSize