param(
  [string]$base = "http://127.0.0.1:8083",
  [string]$email = "u101@goosage.test",
  [string]$password = "1234",
  [long]$targetUserId = 13,

  [int]$openCount = 8,
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

function Save-JsonCompactFile([string]$path, $obj) {
  $json = $obj | ConvertTo-Json -Compress
  [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
}

Ensure-Dir $cookieDir
Ensure-Dir $artifactDir

$ts = Get-Date -Format "yyyyMMdd-HHmmss"

$cookieFile      = Join-Path $cookieDir   "cookie.fake-study.$($targetUserId).txt"
$coachBeforeFile = Join-Path $artifactDir "coach.exp.fake-study.before.u$($targetUserId).$ts.json"
$coachAfterFile  = Join-Path $artifactDir "coach.exp.fake-study.after.u$($targetUserId).$ts.json"
$logFile         = Join-Path $artifactDir "exp.fake-study.u$($targetUserId).$ts.log"

$loginReqFile    = Join-Path $artifactDir "req.fake-study.login.u$($targetUserId).$ts.json"
$eventReqFile    = Join-Path $artifactDir "req.fake-study.event.u$($targetUserId).$ts.json"

Start-Transcript -Path $logFile -Force | Out-Null

try {
  Write-Step "PATH CHECK"
  Write-Host "scriptRoot  => $scriptRoot"
  Write-Host "projectRoot => $projectRoot"
  Write-Host "cookieDir   => $cookieDir"
  Write-Host "artifactDir => $artifactDir"

  Write-Step "1) LOGIN"

  $loginBodyObj = @{
    email    = $email
    password = $password
  }

  Save-JsonCompactFile $loginReqFile $loginBodyObj
  Write-Host "login req file => $loginReqFile"
  Get-Content $loginReqFile | Out-Host

  $loginRaw = curl.exe -s -c $cookieFile `
    -H "Content-Type: application/json" `
    -X POST "$base/auth/login" `
    --data-binary "@$loginReqFile"

  $loginRaw | Out-Host
  $loginObj = $loginRaw | ConvertFrom-Json

  if (-not $loginObj.success) {
    throw "로그인 실패: $($loginObj.message)"
  }

  if (-not (Test-Path $cookieFile)) {
    throw "쿠키 파일 생성 실패: $cookieFile"
  }

  Write-Host "Cookie file => $cookieFile"

  Write-Step "2) COACH BEFORE"

  $coachBeforeRaw = curl.exe -s -b $cookieFile "$base/study/coach?userId=$targetUserId"
  $coachBeforeRaw | Out-Host
  $coachBeforeObj = $coachBeforeRaw | ConvertFrom-Json

  Save-JsonPretty $coachBeforeFile $coachBeforeObj
  Write-Host "saved: $coachBeforeFile"

  if (-not $coachBeforeObj.success) {
    throw "COACH BEFORE 실패: $($coachBeforeObj.message)"
  }

  Write-Step "3) FAKE STUDY INJECTION (JUST_OPEN x $openCount)"

  for ($i = 1; $i -le $openCount; $i++) {
    $eventBodyObj = @{
      userId = $targetUserId
      type   = "JUST_OPEN"
    }

    Save-JsonCompactFile $eventReqFile $eventBodyObj

    Write-Host "[OPEN $i/$openCount] req file => $eventReqFile"
    Get-Content $eventReqFile | Out-Host

    $eventResp = curl.exe -s -b $cookieFile `
      -H "Content-Type: application/json" `
      -X POST "$base/study/events" `
      --data-binary "@$eventReqFile"

    $eventResp | Out-Host
    $eventObj = $eventResp | ConvertFrom-Json

    if (-not $eventObj.success) {
      throw "이벤트 주입 실패 (OPEN $i/$openCount): $($eventObj.message)"
    }

    Start-Sleep -Milliseconds $sleepMs
  }

  Write-Step "4) COACH AFTER"

  $coachAfterRaw = curl.exe -s -b $cookieFile "$base/study/coach?userId=$targetUserId"
  $coachAfterRaw | Out-Host
  $coachAfterObj = $coachAfterRaw | ConvertFrom-Json

  Save-JsonPretty $coachAfterFile $coachAfterObj
  Write-Host "saved: $coachAfterFile"

  if (-not $coachAfterObj.success) {
    throw "COACH AFTER 실패: $($coachAfterObj.message)"
  }

  Write-Step "5) RESULT SUMMARY"

  $beforeEvents = $coachBeforeObj.data.state.eventsCount
  $afterEvents  = $coachAfterObj.data.state.eventsCount

  $beforeQuiz   = $coachBeforeObj.data.state.quizSubmits
  $afterQuiz    = $coachAfterObj.data.state.quizSubmits

  $beforeWrong  = $coachBeforeObj.data.state.wrongReviews
  $afterWrong   = $coachAfterObj.data.state.wrongReviews

  $afterLevel   = $coachAfterObj.data.prediction.level
  $afterReason  = $coachAfterObj.data.prediction.reasonCode
  $afterAction  = $coachAfterObj.data.nextAction

  Write-Host "Before eventsCount : $beforeEvents"
  Write-Host "After  eventsCount : $afterEvents"
  Write-Host "Before quizSubmits : $beforeQuiz"
  Write-Host "After  quizSubmits : $afterQuiz"
  Write-Host "Before wrongReviews: $beforeWrong"
  Write-Host "After  wrongReviews: $afterWrong"
  Write-Host "After prediction   : $afterLevel / $afterReason"
  Write-Host "After nextAction   : $afterAction"

  Write-Step "6) INTERPRETATION"
  Write-Host "- JUST_OPEN만 반복했으므로 진짜 학습 증가 없이 eventsCount만 오를 수 있다."
  Write-Host "- 엔진이 이 패턴을 SAFE로 너무 쉽게 올리면 fake-study 취약 가능성이 있다."
  Write-Host "- WARNING 또는 READ_SUMMARY/STUDY 계열 유지면 비교적 정상이다."

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