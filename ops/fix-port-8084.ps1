$port = 8084

$tcp = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
  Select-Object -First 1 -ExpandProperty OwningProcess

if (-not $tcp) {
  Write-Host "[OK] Port $port is free" -ForegroundColor Green
  exit 0
}

if ($tcp -in 0,4) {
  Write-Host "[SKIP] Port $port owned by system PID $tcp (won't kill)" -ForegroundColor Yellow
  exit 0
}

Write-Host "[FIX] Port $port is in use by PID $tcp. Killing..." -ForegroundColor Yellow
Stop-Process -Id $tcp -Force
Write-Host "[FIX] Killed PID $tcp" -ForegroundColor Yellow
