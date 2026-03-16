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
  Where-Object { $_.Name -match "coach\.day24\.gap(1|3|7|14)\.user\d+\." } |
  Sort-Object LastWriteTime

$latest=@{}

foreach($f in $files){
  if($f.Name -match "coach\.day24\.gap(1|3|7|14)\.user(\d+)\."){
    $gap = "gap{0}" -f $Matches[1]
    $uid = [long]$Matches[2]

    if(-not $latest.ContainsKey($uid)){ $latest[$uid]=@{} }
    $latest[$uid][$gap]=$f
  }
}

$rows=@()

foreach($uid in ($latest.Keys | Sort-Object)){

  $g1  = $latest[$uid]["gap1"]
  $g3  = $latest[$uid]["gap3"]
  $g7  = $latest[$uid]["gap7"]
  $g14 = $latest[$uid]["gap14"]

  if($g1 -and $g3 -and $g7 -and $g14){

    $o1  = Get-Content $g1.FullName  -Raw -Encoding utf8 | ConvertFrom-Json
    $o3  = Get-Content $g3.FullName  -Raw -Encoding utf8 | ConvertFrom-Json
    $o7  = Get-Content $g7.FullName  -Raw -Encoding utf8 | ConvertFrom-Json
    $o14 = Get-Content $g14.FullName -Raw -Encoding utf8 | ConvertFrom-Json

    $rows += [pscustomobject]@{
      userId=$uid

      gap1_Level   = Safe-Get $o1  "prediction.level"
      gap1_Reason  = Safe-Get $o1  "prediction.reasonCode"
      gap1_Action  = Safe-Get $o1  "nextAction"

      gap3_Level   = Safe-Get $o3  "prediction.level"
      gap3_Reason  = Safe-Get $o3  "prediction.reasonCode"
      gap3_Action  = Safe-Get $o3  "nextAction"

      gap7_Level   = Safe-Get $o7  "prediction.level"
      gap7_Reason  = Safe-Get $o7  "prediction.reasonCode"
      gap7_Action  = Safe-Get $o7  "nextAction"

      gap14_Level  = Safe-Get $o14 "prediction.level"
      gap14_Reason = Safe-Get $o14 "prediction.reasonCode"
      gap14_Action = Safe-Get $o14 "nextAction"
    }
  }
}

$rows | Format-Table -AutoSize