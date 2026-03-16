param(
  [string]$base = "http://127.0.0.1:8083",
  [string]$email = "u101@goosage.test",
  [string]$password = "1234",
  [long]$targetUserId = 13,

  [int]$quizCount = 5,
  [int]$sleepMs = 300,

  [switch]$ResetToday = $true
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

function Exec-MySql([string]$sql) {
  docker exec goosage-mysql mysql -uroot -proot123 goosage -e $sql
}

Ensure-Dir $cookieDir
Ensure-Dir $artifactDir

$ts = Get-Date -Format "yyyyMMdd-HHmmss"

$cookieFile        = Join-Path $cookieDir   "cookie.burnout.$targetUserId.txt"
$coachBeforeFile   = Join-Path $artifactDir "coach.exp.burnout.before.u$targetUserId.$ts.json"
$coachAfterFile    = Join-Path $artifactDir "coach.exp.burnout.after.u$targetUserId.$ts.json"
$loginReqFile      = Join-Path $artifactDir "req.burnout.login.u$targetUserId.$ts.json"
$eventReqFile      = Join-Path $artifactDir "req.burnout.event.u$targetUserId.$ts.json"
$logFile           = Join-Path $artifactDir "exp.burnout.u$targetUserId.$ts.log"

Start-Transcript -Path $logFile -Force | Out-Null

try {
  Write-Step "PATH CHECK"
  Write-Host "scriptRoot  => $scriptRoot"
  Write-Host "projectRoot => $projectRoot"
  Write-Host "cookieDir   => $cookieDir"
  Write-Host "artifactDir => $artifactDir"

  if ($ResetToday) {
    Write-Step "0) RESET TODAY"
    $deleteSql = @"
DELETE FROM study_events
WHERE user_id=$targetUserId
AND DATE(created_at)=CURDATE();
"@
    Exec-MySql $deleteSql
    Write-Host "today events deleted for userId=$targetUserId"
  }

  Write-Step "1) LOGIN"

  $loginBody = @{
    email    = $email
    password = $password
  }

  Save-JsonCompact $loginReqFile $loginBody
  Get-Content $loginReqFile | Out-Host

  $loginRaw = curl.exe -s -c $cookieFile `
    -H "Content-Type: application/json" `
    -X POST "$base/auth/login" `
    --data-binary "@$loginReqFile"

  $loginRaw | Out-Host
  $loginObj = $loginRaw | ConvertFrom-Json

  if (-not $loginObj.success) {
    throw "LOGIN FAILED: $($loginObj.message)"
  }

  Write-Host "Cookie file => $cookieFile"

  Write-Step "2) COACH BEFORE"

  $coachBeforeRaw = curl.exe -s -b $cookieFile "$base/study/coach?userId=$targetUserId"
  $coachBeforeRaw | Out-Host
  $coachBeforeObj = $coachBeforeRaw | ConvertFrom-Json

  Save-JsonPretty $coachBeforeFile $coachBeforeObj
  Write-Host "saved: $coachBeforeFile"

  if (-not $coachBeforeObj.success) {
    throw "COACH BEFORE FAILED: $($coachBeforeObj.message)"
  }

  Write-Step "3) BUILD SAFE BASELINE (QUIZ_SUBMIT x $quizCount)"

  for ($i = 1; $i -le $quizCount; $i++) {
    $eventBody = @{
      userId = $targetUserId
      type   = "QUIZ_SUBMIT"
    }

    Save-JsonCompact $eventReqFile $eventBody

    Write-Host "[QUIZ $i/$quizCount]"
    Get-Content $eventReqFile | Out-Host

    $eventResp = curl.exe -s -b $cookieFile `
      -H "Content-Type: application/json" `
      -X POST "$base/study/events" `
      --data-binary "@$eventReqFile"

    $eventResp | Out-Host
    $eventObj = $eventResp | ConvertFrom-Json

    if (-not $eventObj.success) {
      throw "QUIZ EVENT FAILED ($i/$quizCount): $($eventObj.message)"
    }

    Start-Sleep -Milliseconds $sleepMs
  }

  Write-Step "4) COACH AFTER (SAFE BASELINE CHECK)"

  $coachAfterRaw = curl.exe -s -b $cookieFile "$base/study/coach?userId=$targetUserId"
  $coachAfterRaw | Out-Host
  $coachAfterObj = $coachAfterRaw | ConvertFrom-Json

  Save-JsonPretty $coachAfterFile $coachAfterObj
  Write-Host "saved: $coachAfterFile"

  if (-not $coachAfterObj.success) {
    throw "COACH AFTER FAILED: $($coachAfterObj.message)"
  }

  Write-Step "5) RESULT SUMMARY"

  $beforeLevel  = $coachBeforeObj.data.prediction.level
  $beforeReason = $coachBeforeObj.data.prediction.reasonCode
  $beforeAction = $coachBeforeObj.data.nextAction

  $afterEvents  = $coachAfterObj.data.state.eventsCount
  $afterQuiz    = $coachAfterObj.data.state.quizSubmits
  $afterLevel   = $coachAfterObj.data.prediction.level
  $afterReason  = $coachAfterObj.data.prediction.reasonCode
  $afterAction  = $coachAfterObj.data.nextAction

  Write-Host "Before prediction : $beforeLevel / $beforeReason"
  Write-Host "Before nextAction : $beforeAction"
  Write-Host "After eventsCount : $afterEvents"
  Write-Host "After quizSubmits : $afterQuiz"
  Write-Host "After prediction  : $afterLevel / $afterReason"
  Write-Host "After nextAction  : $afterAction"

  Write-Step "6) INTERPRETATION"
  Write-Host "- 이 스크립트는 burnout 베이스라인(SAFE 상태)을 만드는 용도다."
  Write-Host "- 오늘은 SAFE를 만든 뒤 snapshot을 저장한다."
  Write-Host "- 다음 날 또는 공백 후 같은 userId의 coach를 다시 조회해 WARNING/RISK 전환을 본다."
  Write-Host "- 핵심 지표: daysSinceLastEvent, recentEventCount3d, streakDays, prediction level"

  Write-Step "DONE"
}
catch {
  Write-Host ""
  Write-Host "[ERROR] $($_.Exception.Message)"
  throw
}
finally {
  Stop-Transcript | Out-Null
}