param(
  [string]$base = "http://127.0.0.1:8084",
  [string]$loginFile = ".\samples\http-auth-login.req.json",
  [string]$studyOpenFile = ".\samples\http-study-event.just_open.req.json",
  [string]$studyCompleteFile = ".\samples\http-study-event.wrong_review_done.req.json",
  [string]$qaFile = ".\samples\http-qa.req.json"
)

$ErrorActionPreference = "Stop"

function Read-JsonFileOrNull([string]$path) {
  if (Test-Path $path) {
    return Get-Content $path -Raw -Encoding utf8
  }
  return $null
}

Write-Host "==================================================" -ForegroundColor DarkGray
Write-Host " GooSage 3-min Demo : login -> events -> qa -> coach" -ForegroundColor Green
Write-Host " base = $base" -ForegroundColor DarkGray
Write-Host "==================================================" -ForegroundColor DarkGray

# 세션 유지(쿠키)
$cj = New-Object Microsoft.PowerShell.Commands.WebRequestSession

# 0) HEALTH (선택)
Write-Host "`n==== 0) HEALTH ====" -ForegroundColor Cyan
try {
  irm "$base/health" | ConvertTo-Json -Depth 10
} catch {
  Write-Host "health endpoint failed (skip). server may still be up." -ForegroundColor Yellow
}

# 1) LOGIN
Write-Host "`n==== 1) LOGIN ====" -ForegroundColor Cyan
$loginBody = Read-JsonFileOrNull $loginFile
if (-not $loginBody) {
  throw "loginFile not found: $loginFile"
}

$loginRes = irm -Method Post `
  -Uri "$base/auth/login" `
  -ContentType "application/json" `
  -Body $loginBody `
  -WebSession $cj

$loginRes | ConvertTo-Json -Depth 10

# 2) COACH (BEFORE) - 이벤트 쌓이기 전 상태 확인
Write-Host "`n==== 2) COACH (BEFORE events) ====" -ForegroundColor Cyan
$coachBefore = irm -Method Get `
  -Uri "$base/study/coach" `
  -WebSession $cj
$coachBefore | ConvertTo-Json -Depth 20

# 3) STUDY EVENT - OPEN (필수)
Write-Host "`n==== 3) STUDY EVENT (OPEN) ====" -ForegroundColor Cyan
$openBody = Read-JsonFileOrNull $studyOpenFile
if (-not $openBody) {
  throw "studyOpenFile not found: $studyOpenFile"
}

$evOpen = irm -Method Post `
  -Uri "$base/study/events" `
  -ContentType "application/json" `
  -Body $openBody `
  -WebSession $cj

$evOpen | ConvertTo-Json -Depth 10

# 4) STUDY EVENT - COMPLETE (선택)
Write-Host "`n==== 4) STUDY EVENT (COMPLETE) [optional] ====" -ForegroundColor Cyan
$completeBody = Read-JsonFileOrNull $studyCompleteFile
if ($completeBody) {
  $evComplete = irm -Method Post `
    -Uri "$base/study/events" `
    -ContentType "application/json" `
    -Body $completeBody `
    -WebSession $cj

  $evComplete | ConvertTo-Json -Depth 10
} else {
  Write-Host "skip: file not found: $studyCompleteFile" -ForegroundColor DarkGray
}

# 5) QA / CHATBOT ASK (가능하면 /qa로)
Write-Host "`n==== 5) QA / CHATBOT ASK ====" -ForegroundColor Cyan
$qaBody = Read-JsonFileOrNull $qaFile
if (-not $qaBody) {
  # qa 샘플이 없으면 임시 생성해서라도 데모가 끊기지 않게 함
  $qaBody = @"
{
  "question": "3강이 너무 어렵고 이해가 안 돼요. 지금 뭐부터 하면 좋을까요?"
}
"@
  Write-Host "qaFile not found, using inline question payload." -ForegroundColor Yellow
}

try {
  $qaRes = irm -Method Post `
    -Uri "$base/qa" `
    -ContentType "application/json" `
    -Body $qaBody `
    -WebSession $cj

  $qaRes | ConvertTo-Json -Depth 20
} catch {
  Write-Host "POST /qa failed. If your project uses a different endpoint, change it here." -ForegroundColor Yellow
  Write-Host $_.Exception.Message -ForegroundColor DarkGray
}

# 6) COACH (AFTER) - 이벤트/질문 반영 후 NextAction 확인
Write-Host "`n==== 6) COACH (AFTER events+qa) ====" -ForegroundColor Cyan
$coachAfter = irm -Method Get `
  -Uri "$base/study/coach" `
  -WebSession $cj
$coachAfter | ConvertTo-Json -Depth 30

Write-Host "`n==== CHECKPOINT ====" -ForegroundColor Magenta
Write-Host "If eventsCount stayed 0, your /study/events insert path is still broken." -ForegroundColor Magenta
Write-Host "Fix priority: /study/events -> Service/DAO -> INSERT -> commit -> coach aggregation" -ForegroundColor Magenta