# GooSage DB 자동 백업

$today = Get-Date -Format "yyyy-MM-dd"
$backupDir = "C:\backup"
$mainFile = "$backupDir\goosage.sql"
$datedFile = "$backupDir\goosage_$today.sql"

$mysqldump = "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysqldump.exe"

# 폴더 없으면 생성
if (!(Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir | Out-Null
}

Write-Host "=== GooSage DB Backup ==="

# 1. 매일 덮어쓰기용
& $mysqldump -h 127.0.0.1 -P 3306 -u root -p goosage > $mainFile

# 2. 날짜 파일 생성
Copy-Item $mainFile $datedFile -Force

Write-Host "Backup complete:"
Write-Host $mainFile
Write-Host $datedFile