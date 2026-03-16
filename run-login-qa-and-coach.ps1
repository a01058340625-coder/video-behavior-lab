param(
  [string]$base = "http://127.0.0.1:8084",
  [string]$samplesDir = ".\samples",
  [string]$loginFile = "http-auth-login.req.json",
  [string]$qaFile = "http-qa.req.json"
)

$ErrorActionPreference = "Stop"
$cj = New-Object Microsoft.PowerShell.Commands.WebRequestSession

function Assert-True([bool]$cond, [string]$msg) { if (-not $cond) { throw "ASSERT FAIL: $msg" } }
function ReadJson([string]$dir, [string]$file) {
  $p = Join-Path $dir $file
  Assert-True (Test-Path $p) "Missing file: $p"
  return Get-Content $p -Raw -Encoding utf8
}

Write-Host "==== 0) HEALTH ====" -ForegroundColor DarkCyan
irm -Method Get -Uri "$base/health" | Out-Null
Write-Host "OK"

$loginBody = ReadJson $samplesDir $loginFile
$qaBody    = ReadJson $samplesDir $qaFile

Write-Host "==== 1) LOGIN ====" -ForegroundColor Cyan
$login = irm -Method Post -Uri "$base/auth/login" -ContentType "application/json" -Body $loginBody -WebSession $cj
Assert-True ($login.success -eq $true) "login.success should be true"
Write-Host ("login userId=" + $login.data.id)

Write-Host "==== 1.1) COOKIE CHECK ====" -ForegroundColor DarkCyan
$cookieHeader = $cj.Cookies.GetCookieHeader($base)
Write-Host $cookieHeader
Assert-True ($cookieHeader -match "JSESSIONID") "JSESSIONID cookie missing"

Write-Host "==== 2) COACH (BEFORE) ====" -ForegroundColor Cyan
$c1 = irm -Method Get -Uri "$base/study/coach" -WebSession $cj
Assert-True ($c1.success -eq $true) "coach(before).success should be true"
$e1 = [int]$c1.data.state.eventsCount
Write-Host ("eventsCount(before)=" + $e1)

Write-Host "==== 3) QA ====" -ForegroundColor Cyan
# ⚠️ 여기 엔드포인트가 프로젝트에 따라 다를 수 있음.
# 일단 samples 파일명이 http-qa.req.json 이므로 /qa 로 가정.
$qa = irm -Method Post -Uri "$base/qa" -ContentType "application/json" -Body $qaBody -WebSession $cj
Assert-True ($qa.success -eq $true) "qa.success should be true"
Write-Host "qa ok"

Write-Host "==== 4) COACH (AFTER) ====" -ForegroundColor Cyan
$c2 = irm -Method Get -Uri "$base/study/coach" -WebSession $cj
Assert-True ($c2.success -eq $true) "coach(after).success should be true"
$e2 = [int]$c2.data.state.eventsCount
Write-Host ("eventsCount(after)=" + $e2)

$c2 | ConvertTo-Json -Depth 20 | Out-File -Encoding utf8 .\coach.after.json
Write-Host "saved: .\coach.after.json" -ForegroundColor Yellow
Write-Host "? FLOW OK" -ForegroundColor Green