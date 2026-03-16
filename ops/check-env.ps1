Write-Host ""
Write-Host "===== GooSage ENV CHECK ====="
Write-Host ""

Write-Host "1. Load ENV"
. .\env.ps1

Write-Host ""
Write-Host "2. Docker containers"
docker ps

Write-Host ""
Write-Host "3. API health"
curl.exe http://127.0.0.1:8083/health

Write-Host ""
Write-Host "4. DB connection test"
docker exec goosage-mysql mysql -uroot -proot123 -e "SELECT 1;" 2>$null

Write-Host ""
Write-Host "===== ENV CHECK DONE ====="