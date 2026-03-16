param(
  [ValidateSet("am","pm","close","none")]
  [string]$phase = "none"
)

function Say($msg) {
  $ts = (Get-Date).ToString("HH:mm:ss")
  Write-Host "[$ts] $msg"
}

Say "=== GooSage START ==="

# 1) docker check
Say "1) docker check"
try {
  docker ps | Out-Null
} catch {
  Say "Docker Desktop start"
  Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
  Start-Sleep 20
}

# 2) container check
Say "2) container check"
$names = docker ps --format "{{.Names}}"

if ($names -notcontains "goosage-api" -or $names -notcontains "goosage-mysql") {
  Say "docker compose up -d"
  Set-Location "C:\dev\loosegoose\goosage-api"
  docker compose up -d
}

# 3) health check
Say "3) health check"
$ok = $false
for ($i=0; $i -lt 10; $i++) {
  $code = curl.exe -s -o NUL -w "%{http_code}" "http://127.0.0.1:8083/health"
  if ($code -eq "200") { $ok = $true; break }
  Start-Sleep 2
}

if (-not $ok) {
  Say "api restart"
  docker restart goosage-api | Out-Null
}

# 4) run loop (optional)
if ($phase -ne "none") {
  Say "run-day7 phase=$phase"
  Set-Location "C:\dev\loosegoose\goosage-scripts"
  .\run-day7.ps1 -phase $phase
}

Say "=== GooSage READY ==="