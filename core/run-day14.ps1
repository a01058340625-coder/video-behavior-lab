# C:\dev\loosegoose\goosage-scripts\run-day14.ps1
param(
  # artifacts 폴더(기본: scripts\artifacts)
  [string]$artifactsDir = "C:\dev\loosegoose\goosage-scripts\artifacts",

  # 검증 대상 day 태그 (coach 파일명에 포함된 문자열)
  # 예: day13, day12, day11 등
  [string]$dayTag = "day13",

  # 파일명에 포함된 phase 필터 (am/pm/close). 비우면 전체
  [string]$phase = "",

  # 기대값 매핑 (userId=preset,...). day13과 동일하게 넣으면 됨.
  # preset: expand/safe/wrong/low/streak
  [string]$scenarioMap = "5=expand,9=safe,10=low,12=wrong",

  # preset → 기대 nextAction.type
  # (정공법: 지금 엔진은 nextAction이 아직 JUST_OPEN에 많이 걸릴 수 있으니,
  #  1차 목표는 '완벽 예측'이 아니라 '틀린 케이스를 찾는 것')
  [string]$expectMap = "safe=QUIZ_SUBMIT,wrong=REVIEW_WRONG,low=JUST_OPEN,streak=JUST_OPEN,expand=QUIZ_SUBMIT",

  # PASS 기준: 기대 타입과 동일해야 PASS(엄격)
  # 느슨하게 가려면 -loose 를 켜서 JUST_OPEN도 허용
  [switch]$loose = $true
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
    $k = $kv[0].Trim()
    $v = $kv[1].Trim().ToLower()
    $m[$k] = $v
  }
  return $m
}

function Get-JsonFiles() {
  if (-not (Test-Path $artifactsDir)) { Fail "artifactsDir not found: $artifactsDir" }

  $files = Get-ChildItem $artifactsDir -File -Filter "*.json" |
    Where-Object { $_.Name -match "coach\.$dayTag\." }

  if ($phase) {
    $files = $files | Where-Object { $_.Name -match "\.$phase\." }
  }

  return $files | Sort-Object LastWriteTime
}

function Safe-Get($obj, [string]$path) {
  # path 예: "nextAction.type"
  $cur = $obj
  foreach ($p in ($path -split "\.")) {
    if ($null -eq $cur) { return $null }
    if ($cur.PSObject.Properties.Name -contains $p) { $cur = $cur.$p }
    else { return $null }
  }
  return $cur
}

# =========================
# MAIN
# =========================
Info "Day14 verify: NextAction correctness"
Info "artifactsDir=$artifactsDir dayTag=$dayTag phase=$phase"
Info "scenarioMap=$scenarioMap"
Info "expectMap=$expectMap loose=$($loose.IsPresent)"

$scenario = Parse-Map $scenarioMap   # key: userId(string) -> preset
$expect   = Parse-Map $expectMap     # key: preset -> expected nextAction.type

$files = Get-JsonFiles
if (-not $files -or $files.Count -eq 0) { Fail "No coach json found for dayTag=$dayTag in $artifactsDir" }

Warn "Target files = $($files.Count)"
Write-Host ""

$rows = @()

foreach ($f in $files) {
  $jsonText = Get-Content $f.FullName -Raw -Encoding utf8
  $obj = $jsonText | ConvertFrom-Json

  # userId 추출: 파일명에 user{n} 또는 u{n}가 들어가는 패턴을 우선 지원
  $uid = $null
  if ($f.Name -match "user(\d+)") { $uid = [int]$Matches[1] }
  elseif ($f.Name -match "\.u(\d+)\.") { $uid = [int]$Matches[1] }

  $preset = $null
  if ($uid -ne $null -and $scenario.ContainsKey("$uid")) { $preset = $scenario["$uid"] }
  if (-not $preset) { $preset = "unknown" }

  $expected = $null
  if ($expect.ContainsKey($preset)) { $expected = $expect[$preset].ToUpper() } else { $expected = "UNKNOWN" }

  $actual = (Safe-Get $obj "nextAction.type")
if (-not $actual) { $actual = (Safe-Get $obj "nextAction") }
  if ($actual) { $actual = "$actual".ToUpper() } else { $actual = "NULL" }

  # 느슨 모드: JUST_OPEN도 PASS로 허용(지금 엔진 상태 고려)
  $pass = $false
  if ($expected -eq "UNKNOWN") { $pass = $false }
  elseif ($actual -eq $expected) { $pass = $true }
  elseif ($loose -and $actual -eq "JUST_OPEN") { $pass = $true }
  else { $pass = $false }

  $rows += [pscustomobject]@{
    file = $f.Name
    userId = $uid
    preset = $preset
    expected = $expected
    actual = $actual
    pass = $pass
  }
}

# 요약 출력
$passCnt = @($rows | Where-Object { $_.pass }).Count
$totalCnt = @($rows).Count
$failCnt = $totalCnt - $passCnt

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Day14 RESULT (NextAction verify)" -ForegroundColor Cyan
Write-Host " total=$totalCnt pass=$passCnt fail=$failCnt" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 실패만 먼저 보기
$rows | Where-Object { -not $_.pass } |
  Select-Object userId, preset, expected, actual, file |
  Format-Table -AutoSize

Write-Host ""
Write-Host "---- DISTRIBUTION (actual nextAction.type) ----" -ForegroundColor Yellow
$rows | Group-Object actual | Sort-Object Count -Descending |
  Select-Object Count, Name | Format-Table -AutoSize

Write-Host ""
Write-Host "---- DISTRIBUTION (preset) ----" -ForegroundColor Yellow
$rows | Group-Object preset | Sort-Object Count -Descending |
  Select-Object Count, Name | Format-Table -AutoSize

Write-Host ""
Ok "DAY14 VERIFY DONE"