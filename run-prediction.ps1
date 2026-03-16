# run-prediction.ps1
$ErrorActionPreference = "Stop"

$base = "http://127.0.0.1:8084"
$email = "p5_20260206_113532@goosage.local"
$pw = "1234"   # 네 테스트 비번으로 맞춰

Write-Host "== login =="

$cj = New-Object Microsoft.PowerShell.Commands.WebRequestSession

$loginBody = @{
  email = $email
  password = $pw
} | ConvertTo-Json

$login = irm "$base/auth/login" -Method Post -WebSession $cj -ContentType "application/json" -Body $loginBody
if (-not $login.success) { throw "login failed: $($login.message)" }

Write-Host "== coach =="

$coach = irm "$base/study/coach" -WebSession $cj
if (-not $coach.success) { throw "coach failed: $($coach.message)" }

$level  = $coach.data.prediction.level
$reason = $coach.data.prediction.reason
$streak = $coach.data.state.streakDays
$lastAt = $coach.data.state.lastEventAt
$cnt    = $coach.data.state.eventsCount

Write-Host "prediction.level=$level reason=$reason"
Write-Host "state: streakDays=$streak eventsCount=$cnt lastEventAt=$lastAt"

# ---- Assertions (최소 안전장치)
# 1) streakDays > 0 인데 DATA_POOR(WARNING/최근 데이터 부족) 뜨면 버그
if ($streak -gt 0 -and $reason -eq "최근 데이터 부족") {
  throw "Prediction BUG: streakDays>0 but reason=최근 데이터 부족"
}

# 2) 오늘 eventsCount=0 이고 lastEventAt이 과거면 (공백) -> SAFE면 의심
#    (단, 네 규칙상 STABLE/Safe가 뜰 수도 있으니 '오늘 학습 완료'만 금지로 잠금)
if ($cnt -eq 0 -and $lastAt -ne $null -and $reason -eq "오늘 학습 완료") {
  throw "Prediction BUG: eventsCount=0인데 오늘 학습 완료(SAFE) 뜸"
}

Write-Host "OK: prediction regression passed"