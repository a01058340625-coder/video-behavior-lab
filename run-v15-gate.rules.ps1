param(
  [string]$base = "http://127.0.0.1:8084",
  [string]$samplesDir = ".\samples",

  # 케이스별 로그인 JSON 파일명(샘플 폴더 기준)
  [string]$loginAFile = "http-auth-login.req.json",            # goosage@example.com
  [string]$loginBFile = "http-auth-login.fresh.req.json",      # fresh@test.com (네가 만들 계정)
  [string]$loginCFile = "http-auth-login.streak.req.json",     # streak용 계정(선택)

  # 이벤트 샘플
  [string]$eventFile = "http-study-event.just_open.req.json",

  # mysql.exe 경로(환경변수 우선)
  [string]$mysqlExe = "",

  # DB read-only / write 증명 on/off
  [bool]$assertDbEvidence = $true
)

$ErrorActionPreference = "Stop"

# -----------------------
# helpers
# -----------------------
function Assert-True([bool]$cond, [string]$msg) {
  if (-not $cond) { throw "ASSERT FAIL: $msg" }
}

function ReadJson([string]$dir, [string]$file) {
  $p = Join-Path $dir $file
  Assert-True (Test-Path $p) "Missing file: $p"
  return Get-Content $p -Raw -Encoding utf8
}

function RequireEnv([string]$name) {
  $v = (Get-Item -Path ("env:" + $name) -ErrorAction SilentlyContinue).Value
  Assert-True (-not [string]::IsNullOrWhiteSpace($v)) ("Missing env: " + $name)
}

function SaveJson([string]$file, $obj) {
  $obj | ConvertTo-Json -Depth 20 | Out-File -Encoding utf8 $file
}

# -----------------------
# env checks
# -----------------------
if ($assertDbEvidence) {
  RequireEnv "GOOSAGE_DB_HOST"
  RequireEnv "GOOSAGE_DB_PORT"
  RequireEnv "GOOSAGE_DB_NAME"
  RequireEnv "GOOSAGE_DB_USER"
  RequireEnv "GOOSAGE_DB_PASS"
}

# mysql exe resolve (env > param > default)
if ([string]::IsNullOrWhiteSpace($mysqlExe)) { $mysqlExe = $env:GOOSAGE_MYSQL_EXE }
if ([string]::IsNullOrWhiteSpace($mysqlExe)) { $mysqlExe = "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe" }

# -----------------------
# DB evidence (proven version from run-v15-gate.ps1)
# -----------------------
function Db-MaxStudyEventId([int]$uid) {
  if (-not (Test-Path $mysqlExe)) { throw "mysql.exe not found: $mysqlExe" }

  $dbHost = $env:GOOSAGE_DB_HOST
  $dbPort = $env:GOOSAGE_DB_PORT
  $dbName = $env:GOOSAGE_DB_NAME
  $dbUser = $env:GOOSAGE_DB_USER
  $dbPass = $env:GOOSAGE_DB_PASS

  Assert-True ([string]::IsNullOrWhiteSpace($dbHost) -eq $false) "Missing env: GOOSAGE_DB_HOST"
  Assert-True ([string]::IsNullOrWhiteSpace($dbPort) -eq $false) "Missing env: GOOSAGE_DB_PORT"
  Assert-True ([string]::IsNullOrWhiteSpace($dbName) -eq $false) "Missing env: GOOSAGE_DB_NAME"
  Assert-True ([string]::IsNullOrWhiteSpace($dbUser) -eq $false) "Missing env: GOOSAGE_DB_USER"
  Assert-True ([string]::IsNullOrWhiteSpace($dbPass) -eq $false) "Missing env: GOOSAGE_DB_PASS"

  $out = & $mysqlExe `
    -h $dbHost `
    -P $dbPort `
    -u $dbUser `
    "-p$dbPass" `
    $dbName `
    -N -e "SELECT IFNULL(MAX(id),0) FROM study_events WHERE user_id=$uid;"

  return [int]$out
}

# -----------------------
# HTTP: per-case session
# -----------------------
function New-WebSession() {
  return New-Object Microsoft.PowerShell.Commands.WebRequestSession
}

function Login([Microsoft.PowerShell.Commands.WebRequestSession]$cj, [string]$loginFile) {
  Write-Host "==== LOGIN ====" -ForegroundColor Cyan
  $loginBody = ReadJson $samplesDir $loginFile
  $login = irm -Method Post -Uri "$base/auth/login" -ContentType "application/json" -Body $loginBody -WebSession $cj
  Assert-True ($login.success -eq $true) "login.success should be true"
  Write-Host ("login userId=" + $login.data.id)

  Write-Host "==== COOKIE CHECK ====" -ForegroundColor DarkCyan
  $cookieHeader = $cj.Cookies.GetCookieHeader($base)
  Write-Host $cookieHeader
  Assert-True ($cookieHeader -match "JSESSIONID") "JSESSIONID cookie missing"

  return $login.data.id
}

function Coach([Microsoft.PowerShell.Commands.WebRequestSession]$cj) {
  return irm -Method Get -Uri "$base/study/coach" -WebSession $cj
}

function PostEvent([Microsoft.PowerShell.Commands.WebRequestSession]$cj) {
  $eventBody = ReadJson $samplesDir $eventFile
  $ev = irm -Method Post -Uri "$base/study/events" -ContentType "application/json" -Body $eventBody -WebSession $cj
  Assert-True ($ev.success -eq $true) "event.success should be true"
  Write-Host "event ok"
}

function SaveJson([string]$path, $obj) {
  $obj | ConvertTo-Json -Depth 20 | Out-File -Encoding utf8 $path
  Write-Host ("saved: " + $path) -ForegroundColor Yellow
}

# -----------------------
# Health
# -----------------------
Write-Host "==== 0) HEALTH ====" -ForegroundColor DarkCyan
irm -Method Get -Uri "$base/health" | Out-Null
Write-Host "OK"

# =========================
# CASE A: TODAY_DONE (event + coach)
# =========================
Write-Host "===============================" -ForegroundColor Yellow
Write-Host "CASE A) TODAY_DONE (loginAFile=$loginAFile)" -ForegroundColor Yellow
Write-Host "===============================" -ForegroundColor Yellow

$cjA = New-WebSession
$uidA = Login $cjA $loginAFile

$db1 = $null; $db2 = $null; $db3 = $null
$coachBefore = $null; $coachAfter = $null

try {
  if ($assertDbEvidence) {
    Write-Host "==== DB MAX(id) (BEFORE COACH) ====" -ForegroundColor DarkYellow
    $db1 = Db-MaxStudyEventId $uidA
    Write-Host ("dbMaxId(beforeCoach)=" + $db1)
  }

  Write-Host "==== COACH (BEFORE) ====" -ForegroundColor Cyan
  $coachBefore = Coach $cjA
  Assert-True ($coachBefore.success -eq $true) "coach(before).success should be true"
  $e1 = [int]$coachBefore.data.state.eventsCount
  Write-Host ("eventsCount(before)=" + $e1)

  if ($assertDbEvidence) {
    Write-Host "==== DB MAX(id) (AFTER COACH BEFORE) ====" -ForegroundColor DarkYellow
    $db2 = Db-MaxStudyEventId $uidA
    Write-Host ("dbMaxId(afterCoachBefore)=" + $db2)
    Assert-True ($db2 -eq $db1) "coach must be read-only: dbMaxId changed ($db1 -> $db2)"
  }

  Write-Host "==== EVENT ====" -ForegroundColor Cyan
  PostEvent $cjA

  if ($assertDbEvidence) {
    Write-Host "==== DB MAX(id) (AFTER EVENT) ====" -ForegroundColor DarkYellow
    $db3 = Db-MaxStudyEventId $uidA
    Write-Host ("dbMaxId(afterEvent)=" + $db3)
    Assert-True ($db3 -gt $db2) "event must insert: dbMaxId did not increase ($db2 -> $db3)"
  }

  Write-Host "==== COACH (AFTER) ====" -ForegroundColor Cyan
  $coachAfter = Coach $cjA
  Assert-True ($coachAfter.success -eq $true) "coach(after).success should be true"
  $e2 = [int]$coachAfter.data.state.eventsCount
  Write-Host ("eventsCount(after)=" + $e2)

  $rcA = [string]$coachAfter.data.prediction.reasonCode
  $naA = [string]$coachAfter.data.nextAction.type
  $r3A = [int]$coachAfter.data.prediction.evidence.recentEventCount3d
  $stA = [int]$coachAfter.data.prediction.evidence.streakDays

  Write-Host "==== ASSERTS (CASE A) ====" -ForegroundColor Magenta
  Assert-True ($rcA -eq "TODAY_DONE") "CASE A reasonCode must be TODAY_DONE, got=$rcA"
  Assert-True ($naA -eq "TODAY_DONE") "CASE A nextAction must be TODAY_DONE, got=$naA"

  Write-Host ("reasonCode(A)=" + $rcA)
  Write-Host ("nextAction(A)=" + $naA)
  Write-Host ("recentEventCount3d(A)=" + $r3A)
  Write-Host ("streakDays(A)=" + $stA)

  Write-Host "? CASE A PASS" -ForegroundColor Green
}
finally {
  if ($coachAfter -ne $null) { SaveJson ".\coach.caseA.after.json" $coachAfter }
  elseif ($coachBefore -ne $null) { SaveJson ".\coach.caseA.before.json" $coachBefore }
}

# =========================
# CASE B: LOW_ACTIVITY_3D (no event; requires fresh user)
# =========================
Write-Host "===============================" -ForegroundColor Yellow
Write-Host "CASE B) LOW_ACTIVITY_3D (loginBFile=$loginBFile)" -ForegroundColor Yellow
Write-Host "===============================" -ForegroundColor Yellow

$cjB = New-WebSession
$coachB = $null

try {
  $uidB = Login $cjB $loginBFile
  Write-Host "==== COACH (B) ====" -ForegroundColor Cyan
  $coachB = Coach $cjB

  $rcB = [string]$coachB.data.prediction.reasonCode
  $naB = [string]$coachB.data.nextAction.type
  Write-Host "==== ASSERTS (CASE B) ====" -ForegroundColor Magenta
  Write-Host ("reasonCode(B)=" + $rcB)
  Write-Host ("nextAction(B)=" + $naB)

  # fresh 유저면 보통 이게 나와야 함
  Assert-True ($rcB -eq "DATA_POOR") "CASE B reasonCode must be DATA_POOR, got=$rcB"

  Write-Host "? CASE B PASS" -ForegroundColor Green
}
finally {
  if ($coachB -ne $null) { SaveJson ".\coach.caseB.json" $coachB }
}

# ===== CASE C: LOW_ACTIVITY_3D (fresh has ONLY yesterday 1 event; today 0) =====
Write-Host "===============================" -ForegroundColor Yellow
Write-Host "CASE C) LOW_ACTIVITY_3D (fresh has ONLY yesterday 1 event; today 0)" -ForegroundColor Yellow
Write-Host "===============================" -ForegroundColor Yellow

$cjC = New-WebSession
$uidC = Login $cjC $loginBFile   # ? fresh 계정으로 로그인

Write-Host "==== COACH (C) ====" -ForegroundColor Cyan
$coachC = Coach $cjC
$rcC = [string]$coachC.data.prediction.reasonCode
$naC = [string]$coachC.data.nextAction.type

Write-Host ("reasonCode(C)=" + $rcC)
Write-Host ("nextAction(C)=" + $naC)

SaveJson ".\coach.caseC.json" $coachC

Assert-True ($rcC -eq "LOW_ACTIVITY_3D") "CASE C reasonCode must be LOW_ACTIVITY_3D, got=$rcC"
Write-Host "? CASE C PASS" -ForegroundColor Green


# ===== CASE D: STREAK_RISK (requires seed with last event >=2 days ago) =====
Write-Host "===============================" -ForegroundColor Yellow
Write-Host "CASE D) STREAK_RISK (loginDFile=$loginCFile)" -ForegroundColor Yellow
Write-Host "===============================" -ForegroundColor Yellow

$cjD = New-WebSession
$coachD = $null

try {
  $uidD = Login $cjD $loginCFile
  Write-Host "==== COACH (D) ====" -ForegroundColor Cyan
  $coachD = Coach $cjD

  $rcD = [string]$coachD.data.prediction.reasonCode
  $naD = [string]$coachD.data.nextAction.type

  Write-Host "==== ASSERTS (CASE D) ====" -ForegroundColor Magenta
  Write-Host ("reasonCode(D)=" + $rcD)
  Write-Host ("nextAction(D)=" + $naD)

  Assert-True ($rcD -eq "STREAK_RISK") "CASE D reasonCode must be STREAK_RISK, got=$rcD"
  Write-Host "? CASE D PASS" -ForegroundColor Green
}
finally {
  if ($coachD -ne $null) { SaveJson ".\coach.caseD.json" $coachD }
}