param(
  [string]$artifactsDir = "C:\dev\loosegoose\goosage-scripts\core\artifacts",

  [string]$dayTag = "day16",

  # userId=expectedStreakDays
  [string]$streakMap = "5=3,9=1,10=0,12=5"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ok($msg){ Write-Host "[OK]  $msg" -ForegroundColor Green }
function Info($msg){ Write-Host "[..]  $msg" -ForegroundColor Cyan }
function Warn($msg){ Write-Host "[!!]  $msg" -ForegroundColor Yellow }
function Fail($msg){ Write-Host "[FAIL] $msg" -ForegroundColor Red; throw $msg }

function Parse-Map([string]$text) {
  $m = @{}
  foreach ($pair in ($text -split ",")) {
    $p = $pair.Trim()
    if (-not $p) { continue }
    $kv = $p -split "=", 2
    if ($kv.Count -ne 2) { continue }
    $uid = [long]($kv[0].Trim())
    $v = [int]($kv[1].Trim())
    $m[$uid] = $v
  }
  return $m
}

function Safe-Get($obj, [string]$path) {
  $cur = $obj
  foreach ($p in ($path -split "\.")) {
    if ($null -eq $cur) { return $null }
    if ($cur.PSObject.Properties.Name -contains $p) { $cur = $cur.$p }
    else { return $null }
  }
  return $cur
}

if (-not (Test-Path $artifactsDir)) {
  Fail "artifactsDir not found: $artifactsDir"
}

Info "Day16 verify: streakDays correctness"
Info "artifactsDir=$artifactsDir"
Info "streakMap=$streakMap"

$expect = Parse-Map $streakMap

$files = Get-ChildItem $artifactsDir -File -Filter "*.json" |
  Where-Object { $_.Name -match "coach\.day16\.close\.user\d+\." } |
  Sort-Object LastWriteTime

if (-not $files -or $files.Count -eq 0) {
  Fail "No coach json found for day16 in $artifactsDir"
}

$latestPerUser = @{}
foreach ($f in $files) {
  if ($f.Name -match "user(\d+)") {
    $uid = [long]$Matches[1]
    $latestPerUser[$uid] = $f
  }
}

$rows = @()

foreach ($uid in $latestPerUser.Keys | Sort-Object) {
  $f = $latestPerUser[$uid]
  $jsonText = Get-Content $f.FullName -Raw -Encoding utf8
  $obj = $jsonText | ConvertFrom-Json

  $actual = Safe-Get $obj "prediction.evidence.streakDays"
  if ($null -eq $actual) { $actual = Safe-Get $obj "state.streakDays" }
  if ($null -eq $actual) { $actual = -1 }

  $expected = 0
  if ($expect.ContainsKey($uid)) { $expected = [int]$expect[$uid] }

  $pass = ([int]$actual -eq [int]$expected)

  $rows += [pscustomobject]@{
    userId = $uid
    expected = $expected
    actual = [int]$actual
    pass = $pass
    file = $f.Name
  }
}

$passCnt = @($rows | Where-Object { $_.pass }).Count
$totalCnt = @($rows).Count
$failCnt = $totalCnt - $passCnt

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Day16 RESULT (streakDays verify)" -ForegroundColor Cyan
Write-Host " total=$totalCnt pass=$passCnt fail=$failCnt" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$rows | Format-Table -AutoSize

Write-Host ""
Write-Host "---- FAIL ONLY ----" -ForegroundColor Yellow
$rows | Where-Object { -not $_.pass } | Format-Table -AutoSize

Write-Host ""
Ok "DAY16 VERIFY DONE"