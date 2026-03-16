param(
  [switch]$docker,
  [string]$base = "",
  [string]$samplesDir = ".\samples",

  [string]$loginFile = "http-auth-login.req.json",
  [string]$knowledgeCreateFile = "http-knowledge-create.req.json",
  [string]$quizSubmitFile = "http-knowledge-quiz-submit.req.json",
  [string]$studyEventFile = "http-study-event.just_open.req.json",

  [int]$timeoutSec = 5
)

# -----------------------------
# 0) Base 결정 (Docker/STS 공용)
# -----------------------------
if ([string]::IsNullOrWhiteSpace($base)) {
  $base = if ($docker) { "http://127.0.0.1:8083" } else { "http://127.0.0.1:8084" }
}

$ErrorActionPreference = "Stop"
$cj = New-Object Microsoft.PowerShell.Commands.WebRequestSession

function ReadJson([string]$dir, [string]$file) {
  if ([string]::IsNullOrWhiteSpace($file)) { throw "File name is null/empty" }
  $p = Join-Path $dir $file
  if (-not (Test-Path $p)) { throw "Missing file: $p" }
  return Get-Content $p -Raw -Encoding utf8
}

function Assert-True([bool]$cond, [string]$msg) {
  if (-not $cond) { throw "ASSERT FAIL: $msg" }
}

function Print-ErrorBody($err) {
  if ($err -and $err.ErrorDetails -and $err.ErrorDetails.Message) {
    Write-Host "BODY: $($err.ErrorDetails.Message)" -ForegroundColor Yellow
  }
}

# -----------------------------
# 1) HEALTH (선택이지만 FM)
# -----------------------------
Write-Host "==== HEALTH ====" -ForegroundColor DarkCyan
try {
  $h = irm -Method Get -Uri "$base/health" -TimeoutSec $timeoutSec
  $ok = ($h -and $h.data -and $h.data.status -eq "UP")
  Assert-True $ok "health status not UP"
  Write-Host "[OK] $base" -ForegroundColor Green
} catch {
  Write-Host "[DOWN] $base" -ForegroundColor Red
  Print-ErrorBody $_
  throw
}

# -----------------------------
# 2) LOGIN
# -----------------------------
Write-Host "==== LOGIN ====" -ForegroundColor Cyan
$loginBody = ReadJson $samplesDir $loginFile

try {
  $loginRes = irm -Method Post `
    -Uri "$base/auth/login" `
    -ContentType "application/json" `
    -Body $loginBody `
    -WebSession $cj `
    -TimeoutSec $timeoutSec

  $loginRes | ConvertTo-Json -Depth 10
  Assert-True ($loginRes.success -eq $true) "login.success should be true"
} catch {
  Write-Host "LOGIN FAILED: $($_.Exception.Message)" -ForegroundColor Red
  Print-ErrorBody $_
  throw
}

# -----------------------------
# 2.1) COOKIE CHECK (세션 잠금)
# -----------------------------
Write-Host "==== COOKIE CHECK ====" -ForegroundColor DarkCyan
$cookieHeader = $cj.Cookies.GetCookieHeader($base)
Write-Host $cookieHeader
Assert-True ($cookieHeader -match "JSESSIONID") "JSESSIONID cookie missing after login"

# -----------------------------
# 3) COACH (BEFORE)
# -----------------------------
Write-Host "==== COACH (BEFORE) ====" -ForegroundColor Cyan
try {
  $coachBefore = irm -Method Get -Uri "$base/study/coach" -WebSession $cj -TimeoutSec $timeoutSec
  $coachBefore | ConvertTo-Json -Depth 10
  Assert-True ($coachBefore.success -eq $true) "coach(before).success should be true"
  $eventsBefore = [int]$coachBefore.data.state.eventsCount
  Write-Host ("eventsCount(before)={0}" -f $eventsBefore) -ForegroundColor DarkGray
} catch {
  Write-Host "COACH(BEFORE) FAILED: $($_.Exception.Message)" -ForegroundColor Red
  Print-ErrorBody $_
  throw
}

# -----------------------------
# 4) CREATE KNOWLEDGE (body 준비 + sourceId 주입)
# -----------------------------
Write-Host "==== CREATE KNOWLEDGE ====" -ForegroundColor Cyan
$bodyObj = (ReadJson $samplesDir $knowledgeCreateFile) | ConvertFrom-Json

# 회귀 잠금: sourceId는 항상 유니크해야 하므로 무조건 주입
$sourceId = [int64]([DateTimeOffset]::Now.ToUnixTimeMilliseconds())
$bodyObj | Add-Member -NotePropertyName "sourceId" -NotePropertyValue $sourceId -Force

$body = $bodyObj | ConvertTo-Json -Depth 20

# -----------------------------
# 4.1) POST /knowledge -> kid 확보 (필수)
# -----------------------------
try {
  $k = irm -Method Post `
    -Uri "$base/knowledge" `
    -ContentType "application/json" `
    -Body $body `
    -WebSession $cj `
    -TimeoutSec $timeoutSec

  $kid = $k.data.id
  if (-not $kid) { throw "knowledge create failed: no id returned. resp=$($k | ConvertTo-Json -Depth 10)" }
  Write-Host "[OK] knowledgeId=$kid" -ForegroundColor Green
} catch {
  Write-Host "KNOWLEDGE CREATE FAILED: $($_.Exception.Message)" -ForegroundColor Red
  Print-ErrorBody $_
  throw
}

# -----------------------------
# 5) QUIZ SUBMIT
# -----------------------------
Write-Host "==== QUIZ SUBMIT ====" -ForegroundColor Cyan
$quizBody = ReadJson $samplesDir $quizSubmitFile

try {
  $qr = irm -Method Post `
    -Uri "$base/knowledge/$kid/quiz/submit" `
    -ContentType "application/json" `
    -Body $quizBody `
    -WebSession $cj `
    -TimeoutSec $timeoutSec

  $qr | ConvertTo-Json -Depth 30
  Assert-True ($qr.success -eq $true) "quiz submit success should be true"
} catch {
  Write-Host "QUIZ SUBMIT FAILED: $($_.Exception.Message)" -ForegroundColor Red
  Print-ErrorBody $_
  throw
}

# -----------------------------
# 6) STUDY EVENT
# -----------------------------
Write-Host "==== STUDY EVENT ====" -ForegroundColor Cyan
$eventBody = ReadJson $samplesDir $studyEventFile

try {
  $ev = irm -Method Post `
    -Uri "$base/study/events" `
    -ContentType "application/json" `
    -Body $eventBody `
    -WebSession $cj `
    -TimeoutSec $timeoutSec

  $ev | ConvertTo-Json -Depth 30
  Assert-True ($ev.success -eq $true) "study event success should be true"
} catch {
  Write-Host "STUDY EVENT FAILED: $($_.Exception.Message)" -ForegroundColor Red
  Print-ErrorBody $_
  throw
}

# -----------------------------
# 7) COACH (AFTER)
# -----------------------------
Write-Host "==== COACH (AFTER) ====" -ForegroundColor Cyan
try {
  $coachAfter = irm -Method Get -Uri "$base/study/coach" -WebSession $cj -TimeoutSec $timeoutSec
  $coachAfter | ConvertTo-Json -Depth 15
  Assert-True ($coachAfter.success -eq $true) "coach(after).success should be true"
  $eventsAfter = [int]$coachAfter.data.state.eventsCount
  Write-Host ("eventsCount(after)={0}" -f $eventsAfter) -ForegroundColor DarkGray
} catch {
  Write-Host "COACH(AFTER) FAILED: $($_.Exception.Message)" -ForegroundColor Red
  Print-ErrorBody $_
  throw
}

# -----------------------------
# 8) BASIC ASSERTS (v1.5 gate 최소)
# -----------------------------
Write-Host "==== ASSERTS ====" -ForegroundColor Magenta

Assert-True ($eventsAfter -eq ($eventsBefore + 1)) "eventsCount should increase by 1 ($eventsBefore -> $eventsAfter)"

$pred = $coachAfter.data.prediction
$rc  = [string]$pred.reasonCode
Assert-True (-not [string]::IsNullOrWhiteSpace($rc)) "prediction.reasonCode should not be empty"
Assert-True ($rc -ne "DEFAULT_FALLBACK") "DEFAULT_FALLBACK must not appear"

$na = [string]$coachAfter.data.nextAction.type
Assert-True (-not [string]::IsNullOrWhiteSpace($na)) "nextAction.type should not be empty"

Write-Host ("reasonCode(after)={0}" -f $rc)
Write-Host ("nextAction(after)={0}" -f $na)

# 저장 (원하면 artifacts로 변경 가능)
$coachAfter | ConvertTo-Json -Depth 20 | Out-File -Encoding utf8 .\coach.after.json
Write-Host "saved: .\coach.after.json" -ForegroundColor Yellow

Write-Host "✅ FLOW OK (Docker/STS 공용)" -ForegroundColor Green