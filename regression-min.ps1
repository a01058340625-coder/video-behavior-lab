param(
  [switch]$docker,
  [string]$base = "",
  [string]$samplesDir = ".\samples",
  [string]$loginFile = "http-auth-login.req.json",
  [string]$eventFile = "http-study-event.just_open.req.json",
  [int]$timeoutSec = 5
)

if ([string]::IsNullOrWhiteSpace($base)) {
  $base = if ($docker) { "http://127.0.0.1:8083" } else { "http://127.0.0.1:8084" }
}

$ErrorActionPreference = "Stop"
$cj = New-Object Microsoft.PowerShell.Commands.WebRequestSession

function ReadJson([string]$dir, [string]$file) {
  $p = Join-Path $dir $file
  if (-not (Test-Path $p)) { throw "Missing file: $p" }
  return Get-Content $p -Raw -Encoding utf8
}

function Assert-True([bool]$cond, [string]$msg) { if (-not $cond) { throw "ASSERT FAIL: $msg" } }

Write-Host "==== HEALTH ====" -ForegroundColor DarkCyan
$h = irm "$base/health" -TimeoutSec $timeoutSec
Assert-True ($h.data.status -eq "UP") "health not UP"
Write-Host "OK"

Write-Host "==== LOGIN ====" -ForegroundColor Cyan
$loginBody = ReadJson $samplesDir $loginFile
$login = irm -Method Post -Uri "$base/auth/login" -ContentType "application/json" -Body $loginBody -WebSession $cj -TimeoutSec $timeoutSec
Assert-True ($login.success -eq $true) "login failed"
Write-Host ("login userId=" + $login.data.id)

Write-Host "==== COACH (BEFORE) ====" -ForegroundColor Cyan
$c1 = irm "$base/study/coach" -WebSession $cj -TimeoutSec $timeoutSec
Assert-True ($c1.success -eq $true) "coach(before) failed"
$e1 = [int]$c1.data.state.eventsCount
Write-Host ("eventsCount(before)=" + $e1)

Write-Host "==== EVENT ====" -ForegroundColor Cyan
$eventBody = ReadJson $samplesDir $eventFile
$ev = irm -Method Post -Uri "$base/study/events" -ContentType "application/json" -Body $eventBody -WebSession $cj -TimeoutSec $timeoutSec
Assert-True ($ev.success -eq $true) "event failed"
Write-Host "event ok"

Write-Host "==== COACH (AFTER) ====" -ForegroundColor Cyan
$c2 = irm "$base/study/coach" -WebSession $cj -TimeoutSec $timeoutSec
Assert-True ($c2.success -eq $true) "coach(after) failed"
$e2 = [int]$c2.data.state.eventsCount
Write-Host ("eventsCount(after)=" + $e2)

# ? 데이터가 이미 있을 수 있으니 '정확히 +1'이 아니라 '증가'만 보장
Assert-True ($e2 -gt $e1) "eventsCount should increase (before=$e1 after=$e2)"

Write-Host "? MIN LOOP OK" -ForegroundColor Green