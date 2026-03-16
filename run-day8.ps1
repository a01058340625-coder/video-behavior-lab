# C:\dev\loosegoose\goosage-scripts\run-day8.ps1
# GooSage Day8 (D8) - 복귀 강화 + 개입(오답/리뷰) + DATA_POOR 탈출 실험
# 사용법:
#   .\run-day8.ps1 -phase am
#   .\run-day8.ps1 -phase pm
#   .\run-day8.ps1 -phase close
#   .\run-day8.ps1 -phase all

param(
  [ValidateSet("am","pm","close","all")]
  [string]$phase = "all",

  # Docker 운영 기준
  [string]$base = "http://127.0.0.1:8083",

  # Docker MySQL 운영 기준
  [string]$dbName = "goosage",
  [string]$dbRootPass = "root123",

  [string]$logDir = ".\artifacts"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# (선택) 사용자가 cd 안 했을 수도 있으니 안전하게 이동
if ($PWD.Path -notlike "*\goosage-scripts*") {
  $maybe = "C:\dev\loosegoose\goosage-scripts"
  if (Test-Path $maybe) { Set-Location $maybe }
}

$ts = Get-Date -Format "yyyyMMdd-HHmmss"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ("day8.{0}.{1}.log" -f $phase,$ts)

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

  # PowerShell 7+에서 native stderr가 에러로 승격되는 이슈 차단 + exit code로만 실패 판정
  $oldEap = $ErrorActionPreference
  $oldNativePref = $null
  if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $oldNativePref = $global:PSNativeCommandUseErrorActionPreference
  }

  try {
    $ErrorActionPreference = "Continue"
    if ($oldNativePref -ne $null) { $global:PSNativeCommandUseErrorActionPreference = $false }

    $out  = docker exec goosage-mysql mysql -uroot "-p$pass" $dbName -e $sql 2>&1
    $exit = $LASTEXITCODE

    $out | ForEach-Object { Log $_ }

    if ($exit -ne 0) {
      throw "DB COUNT failed (exit=$exit). See log for details."
    }
  }
  finally {
    $ErrorActionPreference = $oldEap
    if ($oldNativePref -ne $null) { $global:PSNativeCommandUseErrorActionPreference = $oldNativePref }
  }
}

# ---------------- phases ----------------

function AM() {
  Log "--- AM Inject: 복귀 강화 + 개입(오답/리뷰) + DATA_POOR 탈출 (D8) ---"

  # A) 몰입형(12,13): 과몰입 방지 + '퀴즈 1회'로 정상 유지
  foreach ($u in 12,13) {
    Event $u "JUST_OPEN"
    Start-Sleep -Seconds 5
    Event $u "QUIZ_SUBMIT"
  }

  # B) 유지형(14,15): 최소 유지
  foreach ($u in 14,15) { Event $u "JUST_OPEN" }

  # C) 핵심: u16 복귀 강화(전날 1회 복귀 → 오늘은 '퀴즈'까지)
  Event 16 "JUST_OPEN"
  Start-Sleep -Seconds 5
  Event 16 "QUIZ_SUBMIT"

  # D) 유지/관측(17): 최소 유지
  Event 17 "JUST_OPEN"

  # E) 개입 실험(18): 오답 1회로 nextAction이 REVIEW로 튀는지
  Event 18 "REVIEW_WRONG"

  # F) 오답형(19): 오답 3회(강한 신호)
  1..3 | ForEach-Object { Event 19 "REVIEW_WRONG" }

  # G) DATA_POOR 탈출 실험(21): 딱 1회만 깨우기
  Event 21 "JUST_OPEN"

  # 20: 공백 유지(대조군)
  Log "AM Inject done. (u20 intentionally idle; u21 single wake-up)"

  SnapshotAll "D8 AM"
}

function PM() {
  Log "--- PM Inject: 최소 유지 + 개입 유지(가벼운 확인) (D8) ---"

  # 12,13: JUST_OPEN 1회(과몰입 방지)
  foreach ($u in 12,13) { Event $u "JUST_OPEN" }

  # u16: 복귀 유지(딱 1회)
  Event 16 "JUST_OPEN"

  # u18: 개입 유지(오답 1회만)
  Event 18 "REVIEW_WRONG"

  # u21: DATA_POOR 탈출 유지(딱 1회)
  Event 21 "JUST_OPEN"

  Log "PM Inject done. (14/15/17/19/20 intentionally idle)"
}

function CLOSE() {
  Log "--- CLOSE: 최종 스냅샷 + DB 카운트 (D8) ---"
  SnapshotAll "D8 PM"
  DbCountToday
}

Log ("=== Day8 START phase={0} base={1} ===" -f $phase,$base)
Health

switch ($phase) {
  "am"    { AM }
  "pm"    { PM }
  "close" { CLOSE }
  "all"   { AM; PM; CLOSE }
}

Log ("=== Day8 END phase={0} ===" -f $phase)
Log ("LOG FILE => {0}" -f $logFile)