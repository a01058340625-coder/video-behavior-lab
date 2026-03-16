param(
  [string]$artifactsDir = "C:\dev\loosegoose\goosage-scripts\core\artifacts",
  [string]$recent3dMap = "5=1,9=3,10=7,12=12"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ok($m){ Write-Host "[OK]  $m" -ForegroundColor Green }
function Info($m){ Write-Host "[..]  $m" -ForegroundColor Cyan }
function Fail($m){ Write-Host "[FAIL] $m" -ForegroundColor Red; throw $m }

function Parse-Map([string]$text){
  $m=@{}
  foreach($pair in ($text -split ",")){
    $p=$pair.Trim(); if(-not $p){ continue }
    $kv=$p -split "=",2
    if($kv.Count -ne 2){ continue }
    $m[[long]$kv[0].Trim()] = [int]$kv[1].Trim()
  }
  return $m
}

function Safe-Get($obj,[string]$path){
  $cur=$obj
  foreach($p in ($path -split "\.")){
    if($null -eq $cur){ return $null }
    if($cur.PSObject.Properties.Name -contains $p){ $cur=$cur.$p } else { return $null }
  }
  return $cur
}

$expect = Parse-Map $recent3dMap

$files = Get-ChildItem $artifactsDir -File -Filter "*.json" |
  Where-Object { $_.Name -match "coach\.day17\.close\.user\d+\." } |
  Sort-Object LastWriteTime

if(-not $files){ Fail "No day17 files" }

$latest=@{}
foreach($f in $files){
  if($f.Name -match "user(\d+)"){ $latest[[long]$Matches[1]] = $f }
}

$rows=@()
foreach($uid in ($latest.Keys | Sort-Object)){
  $obj = (Get-Content $latest[$uid].FullName -Raw -Encoding utf8 | ConvertFrom-Json)
  $actual = Safe-Get $obj "prediction.evidence.recentEventCount3d"
  if($null -eq $actual){ $actual = Safe-Get $obj "state.recentEventCount3d" }
  if($null -eq $actual){ $actual = -1 }

  $expected = 0
  if($expect.ContainsKey($uid)){ $expected = $expect[$uid] }

  $rows += [pscustomobject]@{
    userId=$uid
    expected=$expected
    actual=[int]$actual
    pass=([int]$actual -eq [int]$expected)
    file=$latest[$uid].Name
  }
}

$rows | Format-Table -AutoSize
Ok "DAY17 VERIFY DONE"