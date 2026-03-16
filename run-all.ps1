param(
  [switch]$docker,
  [string]$base = "",
  [string]$loginFile = ".\samples\http-auth-login.req.json",
  [string]$regressionFile = ".\regression-v1.3.ps1",
  [int]$timeoutSec = 1
)

$ErrorActionPreference = "Stop"

# base 결정 규칙: 명시(base) > -docker > default(STS)
if ([string]::IsNullOrWhiteSpace($base)) {
  $base = if ($docker) { "http://127.0.0.1:8083" } else { "http://127.0.0.1:8084" }
}

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
chcp 65001 | Out-Null

# --- transcript log (8-8 proof) ---
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$logDir = Join-Path $here "artifacts"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$logPath = Join-Path $logDir "run-all.log"
Start-Transcript -Path $logPath -Append | Out-Null

function Health-Up($base) {
  try {
    $res = irm "$base/health" -TimeoutSec $timeoutSec
    return ($res -and $res.data -and $res.data.status -eq "UP")
  } catch {
    return $false
  }
}

try {
  Write-Host "==== HEALTH CHECK ====" -ForegroundColor Cyan
  if (Health-Up $base) {
    Write-Host "[OK] Server is UP: $base" -ForegroundColor Green
  } else {
    Write-Host "[DOWN] Server is not reachable: $base" -ForegroundColor Yellow
    if ($docker) {
      Write-Host "-> Start GooSage via Docker (port 8083), then re-run: .\run-all.ps1 -docker" -ForegroundColor Yellow
    } else {
      Write-Host "-> Start GooSage API in STS (port 8084), then re-run: .\run-all.ps1" -ForegroundColor Yellow
      Write-Host "   or run Docker mode: .\run-all.ps1 -docker" -ForegroundColor Yellow
    }
    exit 1
  }

  Write-Host ""
  Write-Host "==== RUN REGRESSION ====" -ForegroundColor Cyan

  # --- loginFile fallback lock ---
  if (-not (Test-Path $loginFile)) {
    Write-Host "[WARN] loginFile not found. fallback to http-auth-login.req.json" -ForegroundColor Yellow
    $loginFile = ".\samples\http-auth-login.req.json"
  }

  & $regressionFile -base $base -samplesDir ".\samples" -loginFile (Split-Path $loginFile -Leaf)
  Write-Host ""
  Write-Host "==== DONE ====" -ForegroundColor Green
}
finally {
  Stop-Transcript | Out-Null
  Write-Host "log saved: $logPath" -ForegroundColor DarkGray
}