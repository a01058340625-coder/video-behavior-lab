param(
  [string]$base = "http://127.0.0.1:8084",
  [int]$userId = 9,
  [string]$method = "GET"
)

$ErrorActionPreference = "Stop"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " run-coach-check : login -> coach -> db(before/after)" -ForegroundColor Cyan
Write-Host " base=$base userId=$userId method=$method" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# -------------------------------
# 0) HEALTH
# -------------------------------
Write-Host "`n==== HEALTH ====" -ForegroundColor Yellow
try {
  irm "$base/health" | Out-Null
  Write-Host "OK"
} catch {
  Write-Host "Health check failed" -ForegroundColor Red
  exit 1
}

# -------------------------------
# 1) LOGIN
# -------------------------------
Write-Host "`n==== LOGIN ====" -ForegroundColor Yellow
$cj = New-Object Microsoft.PowerShell.Commands.WebRequestSession

$loginResp = irm -Method Post `
  -Uri "$base/auth/login" `
  -ContentType "application/json" `
  -Body (Get-Content "..\samples\http-auth-login.req.json" -Raw -Encoding utf8) `
  -WebSession $cj

$loginResp | Format-Table

# -------------------------------
# MYSQL PATH (너 환경에 맞게)
# -------------------------------
$mysql = "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"

# -------------------------------
# 2) DB BEFORE
# -------------------------------
Write-Host "`n==== DB BEFORE (MAX ID) ====" -ForegroundColor Yellow

$beforeMax = & $mysql `
  -h $env:GOOSAGE_DB_HOST `
  -P $env:GOOSAGE_DB_PORT `
  -u $env:GOOSAGE_DB_USER `
  "-p$env:GOOSAGE_DB_PASS" `
  $env:GOOSAGE_DB_NAME `
  -N -e "SELECT IFNULL(MAX(id),0) FROM study_events WHERE user_id=$userId;"

Write-Host "Before MAX(id) = $beforeMax"

# -------------------------------
# 3) COACH
# -------------------------------
Write-Host "`n==== COACH (1 call) ====" -ForegroundColor Yellow

if ($method -eq "POST") {
  $coachResp = irm -Method Post `
    -Uri "$base/study/coach" `
    -WebSession $cj
} else {
  $coachResp = irm -Method Get `
    -Uri "$base/study/coach" `
    -WebSession $cj
}

$coachResp | ConvertTo-Json -Depth 5

# -------------------------------
# 4) DB AFTER
# -------------------------------
Write-Host "`n==== DB AFTER (MAX ID) ====" -ForegroundColor Yellow

$afterMax = & $mysql `
  -h $env:GOOSAGE_DB_HOST `
  -P $env:GOOSAGE_DB_PORT `
  -u $env:GOOSAGE_DB_USER `
  "-p$env:GOOSAGE_DB_PASS" `
  $env:GOOSAGE_DB_NAME `
  -N -e "SELECT IFNULL(MAX(id),0) FROM study_events WHERE user_id=$userId;"

Write-Host "After MAX(id) = $afterMax"

# -------------------------------
# 5) RESULT
# -------------------------------
Write-Host "`n==== RESULT ====" -ForegroundColor Cyan

if ($beforeMax -eq $afterMax) {
  Write-Host "PASS : coach is READ-ONLY" -ForegroundColor Green
} else {
  Write-Host "FAIL : coach INSERT detected" -ForegroundColor Red
}

Write-Host "`nDONE."



