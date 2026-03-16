param(
  # boot: docker up + check
  # am/pm/close/all: boot + check + day phase + (close면 backup까지)
  [ValidateSet("boot","check","am","pm","close","all")]
  [string]$mode = "all",

  # paths
  [string]$ApiDir = "C:\dev\loosegoose\goosage-api",
  [string]$ScriptsDir = "C:\dev\loosegoose\goosage-scripts",

  # base url
  [string]$Base = "http://127.0.0.1:8083",

  # day script (원하는 day로 바꿔치기 가능)
  [string]$DayScript = ".\run-day10.ps1",

  # check script
  [string]$CheckScript = ".\run-check.ps1",

  # coach 우회(401) 기본
  [switch]$NoCoach = $true,

  # DB backup options
  [switch]$DoBackup = $true,
  [string]$BackupDir = "C:\backup",
  [string]$DbName = "goosage",
  [string]$DbRootPass = "root123",
  [string]$MysqlContainer = "goosage-mysql"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function TS(){ (Get-Date).ToString("yyyyMMdd-HHmmss") }
function Log($msg){ Write-Host ("[{0}] {1}" -f (Get-Date).ToString("HH:mm:ss"), $msg) }
function Ok($msg){ Write-Host ("[OK]  {0}" -f $msg) -ForegroundColor Green }
function Warn($msg){ Write-Host ("[WARN] {0}" -f $msg) -ForegroundColor Yellow }
function Fail($msg){ Write-Host ("[FAIL] {0}" -f $msg) -ForegroundColor Red }

function Ensure-Dir($p){
  if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
}

function Assert-File($p, $label){
  if (-not (Test-Path $p)) { throw "$label not found: $p" }
}

function DockerUp(){
  Log "=== DOCKER UP ==="
  Push-Location $ApiDir
  try {
    docker compose up -d | Out-Host
  } finally {
    Pop-Location
  }
  Ok "docker compose up -d done"
}

function Health(){
  Log "=== HEALTH ==="
  $h = curl.exe -sS "$Base/health"
  if ($h -match '"status"\s*:\s*"UP"' -or $h -match '"UP"') { Ok "health UP" }
  else { Warn "health unexpected: $h" }
}

function RunCheck(){
  Log "=== RUN CHECK ==="
  Push-Location $ScriptsDir
  try {
    Assert-File $CheckScript "CheckScript"
    & $CheckScript | Out-Host
  } finally {
    Pop-Location
  }
  Ok "run-check done"
}

function RunDayPhase($phase){
  Log "=== RUN DAY ($phase) ==="
  Push-Location $ScriptsDir
  try {
    Assert-File $DayScript "DayScript"

    if ($NoCoach) {
      & $DayScript -phase $phase | Out-Host
    } else {
      & $DayScript -phase $phase -NoCoach:$false | Out-Host
    }
  } finally {
    Pop-Location
  }
  Ok "run-day $phase done"
}

function BackupDb(){
  if (-not $DoBackup) { Warn "backup skipped (DoBackup=false)"; return }

  Log "=== BACKUP DB ==="
  Ensure-Dir $BackupDir
  $today = (Get-Date).ToString("yyyy-MM-dd")
  $outFile = Join-Path $BackupDir ("goosage_{0}.sql" -f $today)

  # 컨테이너 내부 mysqldump -> 호스트 파일로 리다이렉트
  docker exec $MysqlContainer mysqldump -uroot "-p$DbRootPass" --databases $DbName `
    --single-transaction --routines --triggers --set-gtid-purged=OFF `
    > $outFile

  $len = (Get-Item $outFile).Length
  if ($len -le 0) { throw "backup failed (0 bytes): $outFile" }

  Ok "backup OK => $outFile ($len bytes)"
}

# ---------------- MAIN ----------------
Log "MODE=$mode  Base=$Base  NoCoach=$NoCoach  DayScript=$DayScript"

switch ($mode) {
  "boot" {
    DockerUp
    Health
  }
  "check" {
    Health
    RunCheck
  }
  "am" {
    DockerUp
    Health
    RunCheck
    RunDayPhase "am"
  }
  "pm" {
    DockerUp
    Health
    RunCheck
    RunDayPhase "pm"
  }
  "close" {
    DockerUp
    Health
    RunCheck
    RunDayPhase "close"
    BackupDb
  }
  "all" {
    DockerUp
    Health
    RunCheck
    RunDayPhase "am"
    RunDayPhase "pm"
    RunDayPhase "close"
    BackupDb
  }
}
Log "=== DONE ==="