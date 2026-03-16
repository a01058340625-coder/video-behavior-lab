param(
  [string]$base = "http://127.0.0.1:8083",
  [string]$email = "u101@goosage.test",
  [string]$password = "1234",
  [long]$targetUserId = 13,

  [int[]]$quizCases = @(3,4,5),

  [int]$sleepMs = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot  = $PSScriptRoot
$projectRoot = (Resolve-Path (Join-Path $scriptRoot "..\..")).Path

$cookieDir   = Join-Path $projectRoot "core\cookies"
$artifactDir = Join-Path $projectRoot "core\artifacts"

function Write-Step($msg){
    Write-Host ""
    Write-Host "==== $msg ===="
}

function SaveJson($path,$obj){
    $json = $obj | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($path,$json,[System.Text.UTF8Encoding]::new($false))
}

Write-Step "LOGIN"

$loginFile = Join-Path $artifactDir "req.quiz-threshold.login.json"

$loginBody = @{
  email = $email
  password = $password
}

SaveJson $loginFile $loginBody

$cookieFile = Join-Path $cookieDir "cookie.quiz-threshold.txt"

$loginRaw = curl.exe -s -c $cookieFile `
  -H "Content-Type: application/json" `
  -X POST "$base/auth/login" `
  --data-binary "@$loginFile"

$loginRaw | Out-Host

$loginObj = $loginRaw | ConvertFrom-Json

if(-not $loginObj.success){
    throw "LOGIN FAILED"
}

foreach($quizCount in $quizCases){

    Write-Step "QUIZ CASE = $quizCount"

    $eventFile = Join-Path $artifactDir "req.quiz-threshold.event.json"

    for($i=1; $i -le $quizCount; $i++){

        $eventBody = @{
          userId = $targetUserId
          type   = "QUIZ_SUBMIT"
        }

        SaveJson $eventFile $eventBody

        Write-Host "QUIZ $i / $quizCount"

        $resp = curl.exe -s -b $cookieFile `
          -H "Content-Type: application/json" `
          -X POST "$base/study/events" `
          --data-binary "@$eventFile"

        $resp | Out-Host

        Start-Sleep -Milliseconds $sleepMs
    }

    Write-Step "COACH RESULT"

    $coachRaw = curl.exe -s -b $cookieFile "$base/study/coach?userId=$targetUserId"

    $coachRaw | Out-Host

    $coachObj = $coachRaw | ConvertFrom-Json

    $quizSubmits = $coachObj.data.state.quizSubmits
    $level       = $coachObj.data.prediction.level
    $reason      = $coachObj.data.prediction.reasonCode
    $action      = $coachObj.data.nextAction

    Write-Host ""
    Write-Host "quizSubmits = $quizSubmits"
    Write-Host "prediction  = $level / $reason"
    Write-Host "nextAction  = $action"
}