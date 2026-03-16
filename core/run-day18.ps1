param(
  [string]$artifactsDir = "C:\dev\loosegoose\goosage-scripts\core\artifacts",
  [string]$dslMap = "5=0,9=1,10=3,12=7"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ok($m){ Write-Host "[OK]  $m" -ForegroundColor Green }
function Info($m){ Write-Host "[..]  $m" -ForegroundColor Cyan }
function Fail($m){ Write-Host "[FAIL] $m" -ForegroundColor Red; throw $m }

function Parse-Map([string]$text){
  $m=@{}
  foreach($pair in ($text -split ",")){
    $p=$pair.Trim()
    if(-not $p){ continue }
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
    if($cur.PSObject.Properties.Name -contains $p){
      $cur=$cur.$p
    } else {
      return $null
    }
  }
  return $cur
}

$expect = Parse-Map $dslMap

$files = Get-ChildItem $artifactsDir -File -Filter "*.json" |
  Where-Object { $_.Name -match "coach\.day18\.close\.user\d+\." } |
  Sort-Object LastWriteTime

if(-not $files){ Fail "No day18 files" }

$latest=@{}
foreach($f in $files){
  if($f.Name -match "user(\d+)"){ $latest[[long]$Matches[1]] = $f }
}

$rows=@()
foreach($uid in ($latest.Keys | Sort-Object)){
  $obj = (Get-Content $latest[$uid].FullName -Raw -Encoding utf8 | ConvertFrom-Json)

  $actual = Safe-Get $obj "prediction.evidence.daysSinceLastEvent"
  if($null -eq $actual){ $actual = -1 }

  $expected = 0
  if($expect.ContainsKey($uid)){ $expected = $expect[$uid] }

  $rows += [pscustomobject]@{
    userId   = $uid
    expected = [int]$expected
    actual   = [int]$actual
    pass     = ([int]$actual -eq [int]$expected)
    file     = $latest[$uid].Name
  }
}

$rows | Format-Table -AutoSize
Ok "DAY18 VERIFY DONE"