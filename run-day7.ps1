# C:\dev\loosegoose\goosage-scripts\run-day7.ps1
param(
  [ValidateSet("am","pm","close","all")]
  [string]$phase = "all",

  # Docker 기준(운영): 8083
  [string]$base = "http://127.0.0.1:8083",

  # Docker MySQL 기준(운영)
  [string]$dbName = "goosage",
  [string]$dbRootPass = "root123",

  [string]$logDir = ".\artifacts"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ts = Get-Date -Format "yyyyMMdd-HHmmss"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ("day7.{0}.{1}.log" -f $phase,$ts)

function Log($msg) {
  $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg
  $line | Tee-Object -FilePath $logFile -Append
}

function Health() {
  Log "HEALTH CHECK ($base/health)"
  $out = curl.exe -s "$base/health"
  if (!$out) { throw "HEALTH FAIL: $base/health" }
  Log "HEALTH OK ($base)"
}

function Event($userId, $action) {
  Log ("EVENT u{0} {1}" -f $userId, $action)
  .\run-event.ps1 -userId $userId -action $action -base $base -SkipCoach | Out-Null
}

function SnapshotLine($tag, $uid) {
  $raw = (.\run-coach.ps1 -userId $uid -base $base | Out-String)
  $o = $raw | ConvertFrom-Json
  $d = $o.data
  $line = "{0} u{1} | events={2} wrong={3} quiz={4} | streak={5} dsl={6} recent3d={7} | pred={8}/{9} | next={10}" -f `
    $tag, $uid, $d.state.eventsCount, $d.state.wrongReviews, $d.state.quizSubmits, `
    $d.prediction.evidence.streakDays, $d.prediction.evidence.daysSinceLastEvent, $d.prediction.evidence.recentEventCount3d, `
    $d.prediction.level, $d.prediction.reasonCode, $d.nextAction.type
  Log $line
}

function SnapshotAll($tag) {
  Log ("--- {0} SNAPSHOT (12..21) ---" -f $tag)
  12..21 | ForEach-Object { SnapshotLine $tag $_ }
}

function DbCountToday() {
  Log "--- DB COUNT (today) ---"

  $sql  = "select user_id, count(*) cnt from study_events where date(created_at)=curdate() group by user_id order by user_id;"
  $pass = $dbRootPass.Trim()

  # --- PowerShell 7+ native command stderr 처리 때문에 경고가 에러로 승격되는 문제 차단 ---
  $oldEap = $ErrorActionPreference
  $oldNativePref = $null
  if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $oldNativePref = $global:PSNativeCommandUseErrorActionPreference
  }

  try {
    $ErrorActionPreference = "Continue"
    if ($oldNativePref -ne $null) {
      $global:PSNativeCommandUseErrorActionPreference = $false
    }

    # stderr 포함 캡처 (Warning 포함)
    $out = docker exec goosage-mysql mysql -uroot "-p$pass" $dbName -e $sql 2>&1
    $exit = $LASTEXITCODE

    $out | ForEach-Object { Log $_ }

    if ($exit -ne 0) {
      throw "DB COUNT failed (exit=$exit). See log for details."
    }
  }
  finally {
    $ErrorActionPreference = $oldEap
    if ($oldNativePref -ne $null) {
      $global:PSNativeCommandUseErrorActionPreference = $oldNativePref
    }
  }
}

function AM() {
  Log "--- AM Inject: 패턴 유지 + (u16 1회 복귀 실험) (D7) ---"

  # A) 몰입 유지 (12,13)
  foreach ($u in 12,13) {
    Event $u "JUST_OPEN"
    Start-Sleep -Seconds 10
    Event $u "QUIZ_SUBMIT"
  }

  # B) 유지형 (14,15)
  foreach ($u in 14,15) { Event $u "JUST_OPEN" }

  # C) 핵심 변경 1개: u16을 하루 1회만 살려보기(복귀 실험)
  Event 16 "JUST_OPEN"

  # D) 유지/관측 (17,18)
  Event 17 "JUST_OPEN"
  Event 18 "QUIZ_SUBMIT"

  # E) 오답형 (19)
  1..2 | ForEach-Object { Event 19 "REVIEW_WRONG" }

  # 20,21: 공백 유지(대조군)
  Log "AM Inject done. (20/21 intentionally idle; u16 single revival)"

  SnapshotAll "D7 AM"
}

function PM() {
  Log "--- PM Inject: 과부하 방지(최소 주입) (D7) ---"

  # 12,13 한 번만(과몰입 방지)
  foreach ($u in 12,13) { Event $u "JUST_OPEN" }

  # 17 유지
  Event 17 "JUST_OPEN"

  # 나머지 공백 유지(패턴 관측)
  Log "PM Inject done. (14/15/16/18/19/20/21 intentionally idle)"
}

function CLOSE() {
  Log "--- CLOSE: 오늘 최종 스냅샷 + DB 카운트 (D7) ---"
  SnapshotAll "D7 PM"
  DbCountToday
}

Log ("=== Day7 START phase={0} base={1} ===" -f $phase,$base)
Health

switch ($phase) {
  "am"    { AM }
  "pm"    { PM }
  "close" { CLOSE }
  "all"   { AM; PM; CLOSE }
}

Log ("=== Day7 END phase={0} ===" -f $phase)
Log ("LOG FILE => {0}" -f $logFile)