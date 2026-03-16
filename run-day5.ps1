# run-day5.ps1
# GooSage Day5 (0227) - WARNING 분기 실험
# 사용법:
#   .\run-day5.ps1 -phase am    -base "http://127.0.0.1:8084"
#   .\run-day5.ps1 -phase pm    -base "http://127.0.0.1:8084"
#   .\run-day5.ps1 -phase close -base "http://127.0.0.1:8084" -dbName "goosage_local" -dbUser "goosage"

param(
  [Parameter(Mandatory=$true)]
  [ValidateSet("am","pm","close")]
  [string]$phase,

  [string]$base = "http://127.0.0.1:8084",
  [string]$logDir = ".\artifacts",

  # DB 카운트용 (환경 맞게)
  [string]$mysqlExe = "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe",
  [string]$dbHost = "127.0.0.1",
  [int]$dbPort = 3306,
  [string]$dbUser = "goosage",
  [string]$dbName = "goosage_local"
)

# ✅ param 다음에 둬야 함 (param 위에 두면 파서가 터질 수 있음)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------- helpers ----------------
function Ensure-Dir([string]$p) {
  if (!(Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
}

function NowStamp() { Get-Date -Format "yyyyMMdd-HHmmss" }

function Log([string]$msg) {
  $ts = Get-Date -Format "HH:mm:ss"
  $line = "[$ts] $msg"
  Write-Host $line
  Add-Content -Path $script:logFile -Value $line
}

function Assert-Health([string]$b) {
  $r = curl.exe -s "$b/health"
  if ([string]::IsNullOrWhiteSpace($r)) { throw "health empty response" }

  # GooSage /health 응답이 {"success":true,...} 또는 {"data":{"status":"UP"}} 형태여서 둘 다 허용
  if ($r -notmatch '"status"\s*:\s*"UP"' -and $r -notmatch '"success"\s*:\s*true') {
    throw "health not UP: $r"
  }

  Log "HEALTH OK ($b)"
}

function Run-Event([int]$userId, [string]$action) {
  Log "EVENT u$userId $action"
  .\run-event.ps1 -userId $userId -action $action -base $base -SkipCoach | Out-Null
}

function Db-Count-Today-ByUser() {
  if (!(Test-Path $mysqlExe)) {
    Log "DB COUNT SKIP: mysql.exe not found => $mysqlExe"
    return
  }

  Log "DB COUNT: user별 오늘 이벤트 건수"
  Log "DB => ${dbHost}:${dbPort} / $dbName / $dbUser"

  $sql = @"
select user_id, count(*) as cnt
from study_events
where date(created_at) = curdate()
group by user_id
order by user_id;
"@

  & $mysqlExe `
    --default-character-set=utf8mb4 `
    -h $dbHost `
    -P $dbPort `
    -u $dbUser `
    -p `
    -D $dbName `
    -e $sql |
  ForEach-Object {
    if ($_ -and $_.Trim() -ne "") { Log $_ }
  }
}
# ---------------- bootstrap ----------------
# 사용자가 cd 안 했을 수도 있으니 안전하게 이동 시도
if ($PWD.Path -notlike "*\goosage-scripts*") {
  $maybe = "C:\dev\loosegoose\goosage-scripts"
  if (Test-Path $maybe) { Set-Location $maybe }
}

Ensure-Dir $logDir
$stamp = NowStamp
$script:logFile = Join-Path $logDir "day5.$phase.$stamp.log"

Log "=== Day5 START phase=$phase base=$base ==="
Assert-Health $base

# ---------------- phases ----------------
if ($phase -eq "am") {

  Log "--- AM Inject: WARNING 분기 실험 ---"

  # A) 몰입 유지 (12,13): JUST_OPEN + QUIZ_SUBMIT
  foreach ($u in 12,13) {
    Run-Event $u "JUST_OPEN"
    Start-Sleep 10
    Run-Event $u "QUIZ_SUBMIT"
  }

  # B) 유지형 (14,15): JUST_OPEN 1회
  foreach ($u in 14,15) {
    Run-Event $u "JUST_OPEN"
  }

  # C) 공백/위험 분기 (16~21)
  # 16,20,21 => 의도적으로 아무것도 안 함
  Run-Event 17 "JUST_OPEN"
  Run-Event 18 "QUIZ_SUBMIT"

  # D) 오답형 (19): REVIEW_WRONG 2회
  1..2 | ForEach-Object { Run-Event 19 "REVIEW_WRONG" }

  Log "AM Inject done. (16/20/21 are intentionally idle)"
}
elseif ($phase -eq "pm") {

  Log "--- PM Inject: 번아웃/복귀 유지 확인 ---"

  # 12,13 => JUST_OPEN 1회 (과몰입 방지)
  foreach ($u in 12,13) {
    Run-Event $u "JUST_OPEN"
  }

  # 17 => JUST_OPEN 1회 (미니멈 유지)
  Run-Event 17 "JUST_OPEN"

  Log "PM Inject done. (18/14/15/16/19/20/21 are intentionally idle)"
}
elseif ($phase -eq "close") {

  Log "--- CLOSE: DB 카운트 ---"
  Db-Count-Today-ByUser
}

Log "=== Day5 END phase=$phase ==="
Log "LOG FILE => $script:logFile"