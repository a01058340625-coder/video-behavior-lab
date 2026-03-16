param(
  [string]$base = "http://127.0.0.1:8084",
  [string]$samplesDir = ".\samples",
  [string]$loginFile = "http-auth-login.req.json",
  [string]$eventFile  = "http-study-event.just_open.req.json",

  # 게이트 정책: eventsCount가 정확히 +1이어야 하면 $true
  # 보통은 "증가"만 보장하면 충분하니 기본은 $false
  [bool]$strictPlusOne = $false,

  # ✅ 추가: coach read-only를 DB로 증명할지
  [bool]$assertCoachReadOnly = $true,

  # ✅ 추가: mysql.exe 경로 (너 환경에 맞게)
  [string]$mysqlExe = "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"
)

$ErrorActionPreference = "Stop"
$cj = New-Object Microsoft.PowerShell.Commands.WebRequestSession

function Assert-True([bool]$cond, [string]$msg) { if (-not $cond) { throw "ASSERT FAIL: $msg" } }
function ReadJson([string]$dir, [string]$file) {
  $p = Join-Path $dir $file
  Assert-True (Test-Path $p) "Missing file: $p"
  return Get-Content $p -Raw -Encoding utf8
}

# ✅ 추가: DB MAX(id) 조회 (정공법 증거)
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

$c1 = $null
$c2 = $null
$e1 = $null
$e2 = $null

# ✅ 추가: DB MAX(id) 스냅샷
$db1 = $null
$db2 = $null
$db3 = $null

try {
  Write-Host "==== 0) HEALTH ====" -ForegroundColor DarkCyan
  irm -Method Get -Uri "$base/health" | Out-Null
  Write-Host "OK"

  $loginBody = ReadJson $samplesDir $loginFile
  $eventBody = ReadJson $samplesDir $eventFile

  Write-Host "==== 1) LOGIN ====" -ForegroundColor Cyan
  $login = irm -Method Post -Uri "$base/auth/login" -ContentType "application/json" -Body $loginBody -WebSession $cj
  Assert-True ($login.success -eq $true) "login.success should be true"
  Write-Host ("login userId=" + $login.data.id)

  Write-Host "==== 1.1) COOKIE CHECK ====" -ForegroundColor DarkCyan
  $cookieHeader = $cj.Cookies.GetCookieHeader($base)
  Write-Host $cookieHeader
  Assert-True ($cookieHeader -match "JSESSIONID") "JSESSIONID cookie missing"

  # ✅ 추가: DB BEFORE (정공법 증거)
  if ($assertCoachReadOnly) {
    Write-Host "==== 1.2) DB MAX(id) (BEFORE COACH) ====" -ForegroundColor DarkYellow
    $db1 = Db-MaxStudyEventId $login.data.id
    Write-Host ("dbMaxId(beforeCoach)=" + $db1)
  }

  Write-Host "==== 2) COACH (BEFORE) ====" -ForegroundColor Cyan
  $c1 = irm -Method Get -Uri "$base/study/coach" -WebSession $cj
  Assert-True ($c1.success -eq $true) "coach(before).success should be true"
  $e1 = [int]$c1.data.state.eventsCount
  Write-Host ("eventsCount(before)=" + $e1)

  # ✅ 추가: DB AFTER COACH (read-only 증명)
  if ($assertCoachReadOnly) {
    Write-Host "==== 2.1) DB MAX(id) (AFTER COACH BEFORE) ====" -ForegroundColor DarkYellow
    $db2 = Db-MaxStudyEventId $login.data.id
    Write-Host ("dbMaxId(afterCoachBefore)=" + $db2)
    Assert-True ($db2 -eq $db1) "coach must be read-only: dbMaxId changed ($db1 -> $db2)"
  }

  Write-Host "==== 3) EVENT ====" -ForegroundColor Cyan
  $ev = irm -Method Post -Uri "$base/study/events" -ContentType "application/json" -Body $eventBody -WebSession $cj
  Assert-True ($ev.success -eq $true) "event.success should be true"
  Write-Host "event ok"

  # ✅ 추가: DB AFTER EVENT (write 증명)
  if ($assertCoachReadOnly) {
    Write-Host "==== 3.1) DB MAX(id) (AFTER EVENT) ====" -ForegroundColor DarkYellow
    $db3 = Db-MaxStudyEventId $login.data.id
    Write-Host ("dbMaxId(afterEvent)=" + $db3)
    Assert-True ($db3 -gt $db2) "event must insert: dbMaxId did not increase ($db2 -> $db3)"
  }

  Write-Host "==== 4) COACH (AFTER) ====" -ForegroundColor Cyan
  $c2 = irm -Method Get -Uri "$base/study/coach" -WebSession $cj
  Assert-True ($c2.success -eq $true) "coach(after).success should be true"
  $e2 = [int]$c2.data.state.eventsCount
  Write-Host ("eventsCount(after)=" + $e2)

  # ===== v1.5 GATE =====
  $rc2 = [string]$c2.data.prediction.reasonCode
  $rs13d_2 = [int]$c2.data.prediction.evidence.recentEventCount3d
  $st2 = [int]$c2.data.prediction.evidence.streakDays
  $na2 = [string]$c2.data.nextAction.type

  Write-Host "==== ASSERTS (v1.5 GATE) ====" -ForegroundColor Magenta

  if ($strictPlusOne) {
    Assert-True ($e2 -eq ($e1 + 1)) "eventsCount should increase by +1 ($e1 -> $e2)"
  } else {
    Assert-True ($e2 -gt $e1) "eventsCount should increase ($e1 -> $e2)"
  }

  Assert-True ($rc2 -ne "") "prediction.reasonCode should not be empty"
  Assert-True ($rc2 -ne "DEFAULT_FALLBACK") "DEFAULT_FALLBACK must not appear in gate"
  Assert-True ($rs13d_2 -ge 0) "recentEventCount3d should be >= 0"
  Assert-True ($st2 -ge 0) "streakDays should be >= 0"
  Assert-True ($na2 -ne "") "nextAction.type should not be empty"

  Write-Host ("reasonCode(after)=" + $rc2)
  Write-Host ("nextAction(after)=" + $na2)
  Write-Host ("recentEventCount3d(after)=" + $rs13d_2)
  Write-Host ("streakDays(after)=" + $st2)

  Write-Host "? v1.5 GATE PASS" -ForegroundColor Green
}
finally {
  # 실패해도 마지막 응답 스냅샷은 남긴다(정공법)
  if ($c2 -ne $null) {
    $c2 | ConvertTo-Json -Depth 20 | Out-File -Encoding utf8 .\coach.after.json
    Write-Host "saved: .\coach.after.json" -ForegroundColor Yellow
  } elseif ($c1 -ne $null) {
    $c1 | ConvertTo-Json -Depth 20 | Out-File -Encoding utf8 .\coach.before.json
    Write-Host "saved: .\coach.before.json" -ForegroundColor Yellow
  }
}
