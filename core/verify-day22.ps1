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
  Where-Object { $_.Name -match "coach\.day22\.(baselineA|afterA|baselineB|afterB)\.user\d+\." } |
  Sort-Object LastWriteTime

$latest=@{}

foreach($f in $files){
  if($f.Name -match "coach\.day22\.(baselineA|afterA|baselineB|afterB)\.user(\d+)\."){
    $tag=$Matches[1]
    $uid=[long]$Matches[2]

    if(-not $latest.ContainsKey($uid)){ $latest[$uid]=@{} }
    $latest[$uid][$tag]=$f
  }
}

$rows=@()

foreach($uid in ($latest.Keys | Sort-Object)){

  $baselineAFile = $latest[$uid]["baselineA"]
  $afterAFile    = $latest[$uid]["afterA"]
  $baselineBFile = $latest[$uid]["baselineB"]
  $afterBFile    = $latest[$uid]["afterB"]

  if($baselineAFile -and $afterAFile -and $baselineBFile -and $afterBFile){

    $baselineAObj = Get-Content $baselineAFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json
    $afterAObj    = Get-Content $afterAFile.FullName    -Raw -Encoding utf8 | ConvertFrom-Json
    $baselineBObj = Get-Content $baselineBFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json
    $afterBObj    = Get-Content $afterBFile.FullName    -Raw -Encoding utf8 | ConvertFrom-Json

    $rows += [pscustomobject]@{
      userId=$uid

      baselineA_Level  = Safe-Get $baselineAObj "prediction.level"
      baselineA_Reason = Safe-Get $baselineAObj "prediction.reasonCode"
      afterA_Level     = Safe-Get $afterAObj    "prediction.level"
      afterA_Reason    = Safe-Get $afterAObj    "prediction.reasonCode"
      afterA_Action    = Safe-Get $afterAObj    "nextAction"

      baselineB_Level  = Safe-Get $baselineBObj "prediction.level"
      baselineB_Reason = Safe-Get $baselineBObj "prediction.reasonCode"
      afterB_Level     = Safe-Get $afterBObj    "prediction.level"
      afterB_Reason    = Safe-Get $afterBObj    "prediction.reasonCode"
      afterB_Action    = Safe-Get $afterBObj    "nextAction"
    }
  }
}

$rows | Format-Table -AutoSize