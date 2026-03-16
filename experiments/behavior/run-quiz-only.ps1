param(
  [string]$base = "http://127.0.0.1:8083",
  [string]$email = "u101@goosage.test",
  [string]$password = "1234",
  [long]$targetUserId = 13,

  [int]$quizCount = 10,
  [int]$sleepMs = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot  = $PSScriptRoot
$projectRoot = (Resolve-Path (Join-Path $scriptRoot "..\..")).Path

$cookieDir   = Join-Path $projectRoot "core\cookies"
$artifactDir = Join-Path $projectRoot "core\artifacts"

function Ensure-Dir([string]$path) {
  if (-not (Test-Path $path)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
  }
}

function Write-Step([string]$msg) {
  Write-Host ""
  Write-Host "==== $msg ===="
}

function Save-JsonPretty([string]$path, $obj) {
  $json = $obj | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Save-JsonCompact([string]$path, $obj) {
  $json = $obj | ConvertTo-Json -Compress
  [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
}

Ensure-Dir $cookieDir
Ensure-Dir $artifactDir

$ts = Get-Date -Format "yyyyMMdd-HHmmss"

$cookieFile      = Join-Path $cookieDir   "cookie.quiz-only.$targetUserId.txt"
$coachBeforeFile = Join-Path $artifactDir "coach.exp.quiz-only.before.u$targetUserId.$ts.json"
$coachAfterFile  = Join-Path $artifactDir "coach.exp.quiz-only.after.u$targetUserId.$ts.json"

$loginReqFile = Join-Path $artifactDir "req.quiz-only.login.u$targetUserId.$ts.json"
$eventReqFile = Join-Path $artifactDir "req.quiz-only.event.u$targetUserId.$ts.json"

Write-Step "PATH CHECK"
Write-Host "scriptRoot  => $scriptRoot"
Write-Host "projectRoot => $projectRoot"

Write-Step "1) LOGIN"

$loginBody = @{
  email = $email
  password = $password
}

Save-JsonCompact $loginReqFile $loginBody

$loginRaw = curl.exe -s -c $cookieFile `
  -H "Content-Type: application/json" `
  -X POST "$base/auth/login" `
  --data-binary "@$loginReqFile"

$loginRaw | Out-Host
$loginObj = $loginRaw | ConvertFrom-Json

if (-not $loginObj.success) {
  throw "LOGIN FAILED"
}

Write-Step "2) COACH BEFORE"

$coachBeforeRaw = curl.exe -s -b $cookieFile "$base/study/coach?userId=$targetUserId"
$coachBeforeRaw | Out-Host
$coachBeforeObj = $coachBeforeRaw | ConvertFrom-Json

Save-JsonPretty $coachBeforeFile $coachBeforeObj

if (-not $coachBeforeObj.success) {
  throw "COACH BEFORE FAILED"
}

Write-Step "3) QUIZ ONLY INJECTION"

for ($i = 1; $i -le $quizCount; $i++) {

  $eventBody = @{
    userId = $targetUserId
    type   = "QUIZ_SUBMIT"
  }

  Save-JsonCompact $eventReqFile $eventBody

  Write-Host "[QUIZ $i/$quizCount]"

  $eventResp = curl.exe -s -b $cookieFile `
    -H "Content-Type: application/json" `
    -X POST "$base/study/events" `
    --data-binary "@$eventReqFile"

  $eventResp | Out-Host

  $eventObj = $eventResp | ConvertFrom-Json

  if (-not $eventObj.success) {
    throw "QUIZ EVENT FAILED"
  }

  Start-Sleep -Milliseconds $sleepMs
}

Write-Step "4) COACH AFTER"

$coachAfterRaw = curl.exe -s -b $cookieFile "$base/study/coach?userId=$targetUserId"
$coachAfterRaw | Out-Host
$coachAfterObj = $coachAfterRaw | ConvertFrom-Json

Save-JsonPretty $coachAfterFile $coachAfterObj

Write-Step "5) RESULT"

$beforeEvents = $coachBeforeObj.data.state.eventsCount
$afterEvents  = $coachAfterObj.data.state.eventsCount

$beforeQuiz   = $coachBeforeObj.data.state.quizSubmits
$afterQuiz    = $coachAfterObj.data.state.quizSubmits

$afterLevel   = $coachAfterObj.data.prediction.level
$afterReason  = $coachAfterObj.data.prediction.reasonCode
$afterAction  = $coachAfterObj.data.nextAction

Write-Host "Before eventsCount : $beforeEvents"
Write-Host "After  eventsCount : $afterEvents"

Write-Host "Before quizSubmits : $beforeQuiz"
Write-Host "After  quizSubmits : $afterQuiz"

Write-Host "Prediction : $afterLevel / $afterReason"
Write-Host "NextAction : $afterAction"

Write-Step "DONE"