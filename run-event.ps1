param(
  [Parameter(Mandatory=$true)][int]$userId,
  [Parameter(Mandatory=$true)][ValidateSet("JUST_OPEN","QUIZ_SUBMIT","REVIEW_WRONG")][string]$action,
  [string]$base = "http://127.0.0.1:8083",
  [switch]$SkipCoach
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$cookiesDir = Join-Path $root "cookies"
if (!(Test-Path $cookiesDir)) { New-Item -ItemType Directory -Path $cookiesDir | Out-Null }

$cookie = Join-Path $cookiesDir ("cookie.u{0}.txt" -f $userId)

function Write-Step($t){ Write-Host "==== $t ====" -ForegroundColor Cyan }

Write-Step "LOGIN (cookie saved)"
$loginScript = Join-Path $root "run-login.ps1"
if (!(Test-Path $loginScript)) {
  throw "run-login.ps1가 없습니다: $loginScript"
}
& $loginScript -userId $userId -base $base -cookie $cookie | Out-Host

Write-Step "EVENT POST /study/events ($action)"

# ✅ JSON을 파일로 만들어서 보낸다 (PowerShell quoting 이슈 제거)
$tmpBodyPath = Join-Path $env:TEMP ("goosage.study.event.u{0}.{1}.json" -f $userId, (Get-Date -Format "yyyyMMdd-HHmmss"))
@{
  userId = $userId
  type   = $action
} | ConvertTo-Json -Compress | Out-File -Encoding utf8 $tmpBodyPath

# 디버그용으로 실제 전송 JSON 한 번 찍어주기
Write-Host "payload => $(Get-Content $tmpBodyPath -Raw)" -ForegroundColor DarkGray

$eventRes = curl.exe -s `
  -b $cookie -c $cookie `
  -H "Content-Type: application/json; charset=utf-8" `
  --data-binary "@$tmpBodyPath" `
  "$base/study/events"

if ([string]::IsNullOrWhiteSpace($eventRes)) { throw "event response empty" }
$eventRes | Out-Host

if ($SkipCoach) {
  Write-Host "SKIP COACH" -ForegroundColor Yellow
  exit 0
}

Write-Step "COACH GET /study/coach"
$coachRes = curl.exe -s -b $cookie -c $cookie "$base/study/coach"
if ([string]::IsNullOrWhiteSpace($coachRes)) { throw "coach response empty" }

$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$coachPath = Join-Path $root ("coach.after.u{0}.{1}.json" -f $userId, $ts)
$coachRes | Out-File -Encoding utf8 $coachPath

Write-Host "saved: $coachPath" -ForegroundColor Green
$coachRes | Out-Host