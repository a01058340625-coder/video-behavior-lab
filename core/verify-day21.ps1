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
  Where-Object { $_.Name -match "coach\.day21\.(beforeReturn|afterReturn)\.user\d+\." } |
  Sort-Object LastWriteTime

$latest=@{}

foreach($f in $files){

  if($f.Name -match "coach\.day21\.(beforeReturn|afterReturn)\.user(\d+)\."){

    $tag=$Matches[1]
    $uid=[long]$Matches[2]

    if(-not $latest.ContainsKey($uid)){ $latest[$uid]=@{} }

    $latest[$uid][$tag]=$f
  }
}

$rows=@()

foreach($uid in ($latest.Keys | Sort-Object)){

  $beforeFile = $latest[$uid]["beforeReturn"]
  $afterFile  = $latest[$uid]["afterReturn"]

  if($beforeFile -and $afterFile){

    $beforeObj = (Get-Content $beforeFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json)
    $afterObj  = (Get-Content $afterFile.FullName  -Raw -Encoding utf8 | ConvertFrom-Json)

    $rows += [pscustomobject]@{
      userId=$uid
      beforeLevel=(Safe-Get $beforeObj "prediction.level")
      beforeReason=(Safe-Get $beforeObj "prediction.reasonCode")
      beforeAction=(Safe-Get $beforeObj "nextAction")
      afterLevel=(Safe-Get $afterObj "prediction.level")
      afterReason=(Safe-Get $afterObj "prediction.reasonCode")
      afterAction=(Safe-Get $afterObj "nextAction")
    }
  }
}

$rows | Format-Table -AutoSize