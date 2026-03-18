param(
  [int]$userId = 5,
  [string]$base = "http://127.0.0.1:8083",
  [string]$internalKey = "goosage-dev",

  [string]$mysqlContainer = "goosage-mysql",
  [string]$dbName = "goosage",
  [string]$dbUser = "root",
  [string]$dbPass = "root123",

  [int]$gapDays = 5
)

$ErrorActionPreference = "Stop"

function Post-Event([int]$uid, [string]$type) {
  $body = @{
    userId = $uid
    type   = $type
  } | ConvertTo-Json -Compress

  $res = Invoke-RestMethod `
    -Method Post `
    -Uri "$base/internal/study/events" `
    -Headers @{ "X-INTERNAL-KEY" = $internalKey } `
    -ContentType "application/json" `
    -Body $body

  return $res
}

Write-Host ""
Write-Host "===== FALSE RECOVERY EXPERIMENT =====" -ForegroundColor Cyan
Write-Host ("userId=" + $userId + ", gapDays=" + $gapDays) -ForegroundColor DarkGray
Write-Host ""

# 0. health
Write-Host "[0] health check" -ForegroundColor Yellow
Invoke-RestMethod -Method Get -Uri "$base/health" | Out-Null
Write-Host "[OK] health"
Write-Host ""

# 1. 최근 이벤트를 과거로 밀어서 공백처럼 보이게 만들기
Write-Host "[1] shift recent events to create recovery gap" -ForegroundColor Yellow
docker exec $mysqlContainer mysql -u$dbUser -p$dbPass $dbName -e "
UPDATE study_events
SET created_at = DATE_SUB(created_at, INTERVAL $gapDays DAY)
WHERE user_id = $userId
  AND created_at >= NOW() - INTERVAL 1 DAY;
"
Write-Host "[OK] gap created"
Write-Host ""

# 2. 겉보기 복귀: JUST_OPEN + QUIZ_SUBMIT 소량
Write-Host "[2] inject visible comeback events" -ForegroundColor Yellow
Post-Event -uid $userId -type "JUST_OPEN"   | Out-Null
Post-Event -uid $userId -type "JUST_OPEN"   | Out-Null
Post-Event -uid $userId -type "QUIZ_SUBMIT" | Out-Null
Write-Host "[OK] comeback events injected"
Write-Host ""

# 3. 불안 신호: REVIEW_WRONG + WRONG_REVIEW_DONE
Write-Host "[3] inject unstable signal events" -ForegroundColor Yellow
Post-Event -uid $userId -type "REVIEW_WRONG"       | Out-Null
Post-Event -uid $userId -type "WRONG_REVIEW_DONE"  | Out-Null
Post-Event -uid $userId -type "REVIEW_WRONG"       | Out-Null
Write-Host "[OK] unstable events injected"
Write-Host ""

# 4. DB 확인
Write-Host "[4] DB summary" -ForegroundColor Yellow
docker exec $mysqlContainer mysql -u$dbUser -p$dbPass $dbName -e "
SELECT user_id, type, COUNT(*) cnt
FROM study_events
WHERE user_id = $userId
GROUP BY user_id, type
ORDER BY type;
"
Write-Host ""

# 5. 최근 이벤트 확인
Write-Host "[5] recent events" -ForegroundColor Yellow
docker exec $mysqlContainer mysql -u$dbUser -p$dbPass $dbName -e "
SELECT type, created_at
FROM study_events
WHERE user_id = $userId
ORDER BY created_at DESC
LIMIT 15;
"
Write-Host ""

Write-Host "===== FALSE RECOVERY EXPERIMENT DONE =====" -ForegroundColor Green
Write-Host ""
Write-Host "다음 실행:" -ForegroundColor Cyan
Write-Host "1) core\run-coach.ps1 로 coach 확인"
Write-Host "2) 필요하면 core\run-video-day1.ps1 로 영상 신호 추가"
Write-Host ""