param(
  [string]$ApiDir = "C:\dev\loosegoose\goosage-api",
  [string]$ScriptsDir = "C:\dev\loosegoose\goosage-scripts",
  [string]$ApiBase = "http://127.0.0.1:8084",
  [string]$DbName = "goosage_local",
  [string]$DbRootPass = "1234"
)

function Run($cmd) {
  Write-Host ">> $cmd"
  cmd /c $cmd
  if ($LASTEXITCODE -ne 0) { throw "FAILED: $cmd" }
}

function CurlHealth($url) {
  try {
    $r = Invoke-WebRequest -Uri $url -Method Get -TimeoutSec 3
    return $r.StatusCode
  } catch { return 0 }
}

Write-Host "==== 0) DOCKER: mysql up ===="
Set-Location $ScriptsDir
Run "docker compose up -d"

Write-Host "==== 1) DB: schema check ===="
Run "docker exec -it goosage-mysql mysql -uroot -p$DbRootPass -e ""SHOW DATABASES;"""

Write-Host "==== 2) API: health check ===="
$health = CurlHealth "$ApiBase/health"
if ($health -ne 200) {
  Write-Host "API not up. Start it in a separate window:"
  Write-Host "  cd $ApiDir"
  Write-Host "  .\mvnw.cmd -DskipTests spring-boot:run ""-Dspring-boot.run.arguments=--spring.profiles.active=local"""
  throw "API_DOWN"
}
Write-Host "API health OK (200)"

Write-Host "==== 3) DB: tables check ===="
Run "docker exec -it goosage-mysql mysql -uroot -p$DbRootPass $DbName -e ""SHOW TABLES;"""

Write-Host "==== 4) SEED: ensure userId=12 exists ===="
# 이미 있으면 무시(중복 방지)
Run "docker exec -it goosage-mysql mysql -uroot -p$DbRootPass $DbName -e ""INSERT IGNORE INTO users (id,email,password_hash) VALUES (12,'u12@local','noop');"""
Run "docker exec -it goosage-mysql mysql -uroot -p$DbRootPass $DbName -e ""SELECT id,email FROM users WHERE id=12;"""

Write-Host "==== 5) EVENT: post JUST_OPEN ===="
$uri = "$ApiBase/internal/study/events"
$headers = @{ "X-INTERNAL-KEY" = "goosage-dev" }
$body = @{ userId = 12; type = "JUST_OPEN" } | ConvertTo-Json -Compress
try {
  $res = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType "application/json" -Body $body
  $ok = $res.success
  Write-Host "EVENT POST success=$ok message=$($res.message)"
} catch {
  Write-Host "EVENT POST FAILED (see server console stacktrace)."
  throw
}

Write-Host "==== 6) VERIFY: DB count ===="
Run "docker exec -it goosage-mysql mysql -uroot -p$DbRootPass $DbName -e ""SELECT COUNT(*) cnt FROM study_events WHERE user_id=12;"""
Run "docker exec -it goosage-mysql mysql -uroot -p$DbRootPass $DbName -e ""SELECT id,user_id,type,created_at FROM study_events WHERE user_id=12 ORDER BY id DESC LIMIT 5;"""

Write-Host "==== DONE ===="