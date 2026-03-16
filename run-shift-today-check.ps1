param(
  [string]$base = "http://127.0.0.1:8084",
  [int]$days = 4,
  [long]$userId = 9,
  [string]$loginFile = ".\samples\http-auth-login.req.json"
)

$ErrorActionPreference = "Stop"

function J($p) { Get-Content $p -Raw -Encoding utf8 }

Write-Host "==== 0) NEW SESSION ====" -ForegroundColor Cyan
$cj = New-Object Microsoft.PowerShell.Commands.WebRequestSession

Write-Host "==== 1) LOGIN ====" -ForegroundColor Cyan
if (!(Test-Path $loginFile)) {
  throw "loginFile not found: $loginFile (경로 확인 필요)"
}

$loginBody = J $loginFile
$login = irm -Method Post -Uri "$base/auth/login" -ContentType "application/json" -Body $loginBody -WebSession $cj
Write-Host ("login ok, userId=" + $login.data.id)

Write-Host "==== 1.1) COOKIE CHECK ====" -ForegroundColor Cyan
$cookieHeader = $cj.Cookies.GetCookieHeader($base)
Write-Host $cookieHeader
if ($cookieHeader -notmatch "JSESSIONID=") {
  throw "JSESSIONID not found. 로그인/세션 유지 실패"
}

Write-Host "==== 2) COACH (BEFORE) ====" -ForegroundColor Cyan
$c0 = irm -Method Get -Uri "$base/study/coach" -WebSession $cj
Write-Host ("reasonCode(before)=" + $c0.data.prediction.reasonCode)
Write-Host ("daysSinceLast(before)=" + $c0.data.prediction.evidence.daysSinceLastEvent)
Write-Host ("eventsCount(before)=" + $c0.data.state.eventsCount)

Write-Host "==== 3) SHIFT TODAY EVENTS ====" -ForegroundColor Yellow
# ? 새 엔드포인트 (너가 추가한 것)
# POST /study/debug/shift-today-events?days=4
$r = irm -Method Post -Uri "$base/study/debug/shift-today-events?days=$days" -WebSession $cj
Write-Host ("shift result=" + $r.data)

Write-Host "==== 4) COACH (AFTER) ====" -ForegroundColor Cyan
$c1 = irm -Method Get -Uri "$base/study/coach" -WebSession $cj
Write-Host ("reasonCode(after)=" + $c1.data.prediction.reasonCode)
Write-Host ("daysSinceLast(after)=" + $c1.data.prediction.evidence.daysSinceLastEvent)
Write-Host ("eventsCount(after)=" + $c1.data.state.eventsCount)

Write-Host "==== 5) ASSERT (EXPECT GAP) ====" -ForegroundColor Magenta
if ($c1.data.prediction.evidence.daysSinceLastEvent -ge 3) {
  Write-Host "? PASS: daysSinceLastEvent >= 3" -ForegroundColor Green
} else {
  Write-Host "? FAIL: daysSinceLastEvent still < 3 (오늘 이벤트가 남았거나, lastEventAtAll 계산/조회가 다른 곳을 보고 있을 가능성)" -ForegroundColor Red
}