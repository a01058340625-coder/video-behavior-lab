param(
  [int]$userId = 5,
  [string]$base = "http://127.0.0.1:8083",
  [string]$internalKey = "goosage-dev",

  [string]$walkDir = "C:\dev\loosegoose\walk",
  [string]$samplesDir = "..\samples",

  [string]$mysqlContainer = "goosage-mysql",
  [string]$dbName = "goosage",
  [string]$dbUser = "root",
  [string]$dbPass = "root123"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "===== VIDEO DAY1 PIPELINE =====" -ForegroundColor Cyan
Write-Host ""

# 1. 영상 → 이벤트 변환
Write-Host "[1] convert_to_event.py 실행" -ForegroundColor Yellow
cd $walkDir
python convert_to_event.py

Write-Host "[OK] 영상 → 이벤트 변환 완료"
Write-Host ""

# 2. DB 상태 확인
Write-Host "[2] DB 이벤트 집계 확인" -ForegroundColor Yellow

docker exec $mysqlContainer mysql -u$dbUser -p$dbPass $dbName -e "
SELECT user_id, type, COUNT(*) cnt
FROM study_events
WHERE user_id = $userId
GROUP BY user_id, type
ORDER BY type;
"

Write-Host "[OK] DB 확인 완료"
Write-Host ""

# 3. coach 호출
Write-Host "[3] coach 결과 확인" -ForegroundColor Yellow

cd "C:\dev\loosegoose\goosage-scripts\core"

.\run-coach.ps1 `
  -userId $userId `
  -samplesDir $samplesDir `
  -loginFile "http-auth-login.u5.req.json"

Write-Host ""
Write-Host "===== DONE =====" -ForegroundColor Green
Write-Host ""