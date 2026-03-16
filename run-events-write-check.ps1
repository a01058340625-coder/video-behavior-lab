param(
  [string]$base = "http://127.0.0.1:8084",
  [int]$userId = 9,
  [string]$eventFile = ".\samples\http-study-events.just_open.req.json"
)

$ErrorActionPreference = "Stop"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " run-events-write-check : login -> POST /study/events -> DB id must increase" -ForegroundColor Cyan
Write-Host " base=$base userId=$userId eventFile=$eventFile" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# mysql path (너 환경에 맞게)
$mysql = "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"

function GetMaxId([int]$uid) {
  $out = & $mysql `
    -h $env:GOOSAGE_DB_HOST `
    -P $env:GOOSAGE_DB_PORT `
    -u $env:GOOSAGE_DB_USER `
    "-p$env:GOOSAGE_DB_PASS" `
    $env:GOOSAGE_DB_NAME `
    -N -e "SELECT IFNULL(MAX(id),0) FROM study_events WHERE user_id=$uid;"
  return [int]$out
}

# 0) HEALTH
Write-Host "`n==== HEALTH ====" -ForegroundColor Yellow
irm "$base/health" | Out-Null
Write-Host "OK"

# 1) LOGIN (session)
Write-Host "`n==== LOGIN ====" -ForegroundColor Yellow
$cj = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$loginResp = irm -Method Post `
  -Uri "$base/auth/login" `
  -ContentType "application/json" `
  -Body (Get-Content .\samples\http-auth-login.req.json -Raw -Encoding utf8) `
  -WebSession $cj
$loginResp | Format-Table

if (-not (Test-Path $eventFile)) {
  throw "eventFile not found: $eventFile"
}

# 2) DB BEFORE
Write-Host "`n==== DB BEFORE (MAX ID) ====" -ForegroundColor Yellow
$beforeMax = GetMaxId $userId
Write-Host "Before MAX(id) = $beforeMax"

# 3) POST /study/events (WRITE)
Write-Host "`n==== POST /study/events ====" -ForegroundColor Yellow
$body = Get-Content $eventFile -Raw -Encoding utf8
$resp = irm -Method Post `
  -Uri "$base/study/events" `
  -ContentType "application/json" `
  -Body $body `
  -WebSession $cj
$resp | ConvertTo-Json -Depth 6

# 4) DB AFTER
Write-Host "`n==== DB AFTER (MAX ID) ====" -ForegroundColor Yellow
$afterMax = GetMaxId $userId
Write-Host "After MAX(id) = $afterMax"

# 5) RESULT
Write-Host "`n==== RESULT ====" -ForegroundColor Cyan
if ($afterMax -gt $beforeMax) {
  Write-Host "PASS : /study/events INSERT confirmed (WRITE OK)" -ForegroundColor Green
} else {
  Write-Host "FAIL : /study/events did NOT insert (WRITE BROKEN)" -ForegroundColor Red
}

Write-Host "`nDONE."