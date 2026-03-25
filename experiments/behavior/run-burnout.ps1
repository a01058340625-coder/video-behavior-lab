param(
  [string]$base = "http://127.0.0.1:8084",
  [long]$targetUserId = 13,
  [string]$loginEmail = "u101@goosage.test",
  [string]$loginPassword = "1234",

  [string]$mysqlContainer = "goosage-mysql",
  [string]$dbName = "goosage",
  [string]$dbUser = "root",
  [string]$dbPass = "root123",

  [switch]$ResetToday = $true
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Section($title) {
  Write-Host ""
  Write-Host "==== $title ===="
}

function Ensure-Dir($path) {
  if (-not (Test-Path $path)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
  }
}

function Write-Utf8NoBom([string]$path, [string]$text) {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $text, $utf8NoBom)
}

function Invoke-MySqlFile([string]$sqlFile) {
  $sqlText = Get-Content $sqlFile -Raw

  $sqlText | docker exec -i $mysqlContainer `
    mysql `
    "-u$($dbUser)" `
    "-p$($dbPass)" `
    $dbName

  if ($LASTEXITCODE -ne 0) {
    throw "MYSQL FAILED: exitCode=$LASTEXITCODE"
  }
}

try {
  $scriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
  $projectRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
  $cookieDir   = Join-Path $projectRoot "core\cookies"
  $artifactDir = Join-Path $projectRoot "core\artifacts"
  $ts          = Get-Date -Format "yyyyMMdd-HHmmss"

  Ensure-Dir $cookieDir
  Ensure-Dir $artifactDir

  $cookieFile    = Join-Path $cookieDir "cookie.u$targetUserId.txt"
  $loginReqFile  = Join-Path $artifactDir "req.burnout.login.u$targetUserId.$ts.json"
  $loginRespFile = Join-Path $artifactDir "resp.burnout.login.u$targetUserId.$ts.txt"
  $coachRespFile = Join-Path $artifactDir "coach.burnout.u$targetUserId.$ts.json"
  $sqlFile       = Join-Path $artifactDir "sql.burnout.reset.u$targetUserId.$ts.sql"

  Write-Section "PATH CHECK"
  Write-Host "scriptRoot  => $scriptRoot"
  Write-Host "projectRoot => $projectRoot"
  Write-Host "cookieDir   => $cookieDir"
  Write-Host "artifactDir => $artifactDir"

  if ($ResetToday) {
    Write-Section "0) RESET TODAY"

    $sql = @"
DELETE FROM study_events
WHERE user_id = $targetUserId
  AND created_at >= CURDATE()
  AND created_at < DATE_ADD(CURDATE(), INTERVAL 1 DAY);
"@

   Write-Utf8NoBom $sqlFile $sql
Invoke-MySqlFile $sqlFile
Write-Host "today events deleted for userId=$targetUserId"
  }

  Write-Section "1) LOGIN"

  $loginReq = @{
    email    = $loginEmail
    password = $loginPassword
  } | ConvertTo-Json -Compress

  Write-Utf8NoBom $loginReqFile $loginReq
  Get-Content $loginReqFile -Raw | Out-Host

  if (Test-Path $loginRespFile) {
    Remove-Item $loginRespFile -Force
  }

  $curlErrFile = Join-Path $artifactDir "resp.burnout.login.err.u$targetUserId.$ts.txt"

if (Test-Path $loginRespFile) { Remove-Item $loginRespFile -Force }
if (Test-Path $curlErrFile)   { Remove-Item $curlErrFile -Force }

$oldEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"

$httpCode = & curl.exe `
  -sS `
  -o $loginRespFile `
  -w "%{http_code}" `
  -c $cookieFile `
  -H "Content-Type: application/json" `
  -X POST "$base/auth/login" `
  --data-binary "@$loginReqFile" `
  2> $curlErrFile

$curlExit = $LASTEXITCODE
$ErrorActionPreference = $oldEap

Write-Host "CURL EXIT => $curlExit"
Write-Host "LOGIN HTTP => $httpCode"

if (Test-Path $curlErrFile) {
  $curlErr = Get-Content $curlErrFile -Raw
  if (-not [string]::IsNullOrWhiteSpace($curlErr)) {
    Write-Host "LOGIN STDERR =>"
    $curlErr | Out-Host
  }
}

if ($curlExit -ne 0) {
  throw "LOGIN FAILED: curl exitCode=$curlExit"
}

if (-not (Test-Path $loginRespFile)) {
  throw "LOGIN FAILED: response file not created => $loginRespFile"
}

  $loginRaw = Get-Content $loginRespFile -Raw

  Write-Host "LOGIN HTTP => $httpCode"
  Write-Host "LOGIN RAW =>"
  $loginRaw | Out-Host

  if ([string]::IsNullOrWhiteSpace($loginRaw)) {
    throw "LOGIN FAILED: empty response"
  }

  try {
    $loginObj = $loginRaw | ConvertFrom-Json
  }
  catch {
    throw "LOGIN FAILED: invalid JSON => $loginRaw"
  }

  if ($null -eq $loginObj.PSObject.Properties['success']) {
    throw "LOGIN FAILED: 'success' field missing => $loginRaw"
  }

  if (-not $loginObj.success) {
    throw "LOGIN FAILED: $($loginObj.message)"
  }

  Write-Host "login success"

  Write-Section "2) COACH CHECK"

  $coachRaw = curl.exe -s -b $cookieFile "$base/study/coach"
  Write-Utf8NoBom $coachRespFile $coachRaw

  Write-Host "saved => $coachRespFile"
  $coachRaw | Out-Host

  if ([string]::IsNullOrWhiteSpace($coachRaw)) {
    throw "COACH FAILED: empty response"
  }

  try {
    $coachObj = $coachRaw | ConvertFrom-Json
  }
  catch {
    throw "COACH FAILED: invalid JSON => $coachRaw"
  }

  if ($null -eq $coachObj.PSObject.Properties['success']) {
    throw "COACH FAILED: 'success' field missing => $coachRaw"
  }

  if (-not $coachObj.success) {
    throw "COACH FAILED: $($coachObj.message)"
  }

  Write-Section "DONE"
  Write-Host "run-burnout completed"
}
catch {
  Write-Host ""
  Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
  throw
}