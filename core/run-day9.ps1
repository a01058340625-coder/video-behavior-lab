# C:\dev\loosegoose\goosage-scripts\run-day9.ps1
# GooSage Day9 (D9) - wrongReviews(0) 원인 추적용 루프
# 핵심: 이벤트 주입(REVIEW_WRONG) -> coach 스냅샷 -> DB(study_events / daily_learning) 동시 검증
#
# 사용법:
#   .\run-day9.ps1 -phase am
#   .\run-day9.ps1 -phase pm
#   .\run-day9.ps1 -phase close
#   .\run-day9.ps1 -phase all

param(
  [ValidateSet("am","pm","close","all")]
  [string]$phase = "all",

  # Docker 운영 기준
  [string]$base = "http://127.0.0.1:8083",

  # Docker MySQL 운영 기준
  [string]$dbName = "goosage",
  [string]$dbRootPass = "root123",

  [string]$logDir = ".\artifacts",

  # 이벤트 타입 SSOT 흔들릴 때 여기만 바꿔서 실험
  [string]$wrongType = "REVIEW_WRONG"
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
$logFile = Join-Path $logDir ("day9.{0}.{1}.log" -f $phase,$ts)

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

# PowerShell 7+에서 native stderr가 에러로 승격되는 이슈 차단 + exit code로만 실패 판정
function Invoke-Db($label, $sql, [bool]$fatal = $false) {
  $pass = $dbRootPass.Trim()

  $oldEap = $ErrorActionPreference
  $oldNativePref = $null
  if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $oldNativePref = $global:PSNativeCommandUseErrorActionPreference
  }

  try {
    $ErrorActionPreference = "Continue"
    if ($oldNativePref -ne $null) { $global:PSNativeCommandUseErrorActionPreference = $false }

    Log ("--- DB: {0} ---" -f $label)
    Log ("SQL => {0}" -f $sql)

    $out  = docker exec goosage-mysql mysql -uroot "-p$pass" $dbName -e $sql 2>&1
    $exit = $LASTEXITCODE

    $out | ForEach-Object { Log $_ }

    if ($exit -ne 0) {
      $msg = "DB query failed (exit=$exit) label=$label"
      if ($fatal) { throw $msg } else { Log "WARN: $msg" }
    }
  }
  finally {
    $ErrorActionPreference = $oldEap
    if ($oldNativePref -ne $null) { $global:PSNativeCommandUseErrorActionPreference = $oldNativePref }
  }
}

function DbVerifyToday() {
  Log "--- DB VERIFY (today) ---"

  # 1) 오늘 전체 이벤트(유저별)
  Invoke-Db "study_events count by user(today)" `
    "select user_id, count(*) cnt
     from study_events
     where date(created_at)=curdate()
     group by user_id order by user_id;"

  # 2) 오늘 이벤트(유저+타입별)  <= wrongType이 실제로 저장되는지 바로 보임
  Invoke-Db "study_events count by user+type(today)" `
    "select user_id, type, count(*) cnt
     from study_events
     where date(created_at)=curdate()
     group by user_id, type
     order by user_id, type;"

  # 3) 오답타입만 필터(오늘)
  Invoke-Db "study_events ONLY wrongType(today)" `
    ("select user_id, count(*) cnt
      from study_events
      where date(created_at)=curdate()
        and type='{0}'
      group by user_id order by user_id;" -f $wrongType)

  # 4) daily_learning 집계 확인(테이블/컬럼명이 다를 수 있으니 '가장 가능성 높은 쿼리' 2개를 던져봄)
  #    - 실패해도 WARN만 찍고 진행 (fatal=false)
  Invoke-Db "daily_learning check #1 (today rows)" `
    "select * from daily_learning where date(created_at)=curdate() order by id desc limit 20;"

  Invoke-Db "daily_learning check #2 (user_id, wrong_reviews, today?)" `
    "select user_id, wrong_reviews
     from daily_learning
     where date(created_at)=curdate()
     order by user_id;"
}

# ---------------- phases ----------------

function AM() {
  Log "--- AM Inject (D9): wrongReviews(0) 추적용 강한 신호 주입 ---"
  Log ("wrongType SSOT test => {0}" -f $wrongType)

  # 12,13: 정상 루틴(퀴즈 1회) - 시스템이 살아있는지 기준선
  foreach ($u in 12,13) {
    Event $u "JUST_OPEN"
    Start-Sleep -Seconds 3
    Event $u "QUIZ_SUBMIT"
  }

  # 14,15: 최소 유지
  foreach ($u in 14,15) { Event $u "JUST_OPEN" }

  # u16/u18: "오답 집계 핵심 추적 대상"
  Event 16 "JUST_OPEN"
  Start-Sleep -Seconds 3
  Event 16 "QUIZ_SUBMIT"

  # u18: 오답 2회 (너무 과하면 규칙이 다른 곳으로 튈 수 있어 2회로 시작)
  1..2 | ForEach-Object { Event 18 $wrongType }

  # u19: 오답형 강하게 3회
  1..3 | ForEach-Object { Event 19 $wrongType }

  # u21: DATA_POOR 탈출용 1회
  Event 21 "JUST_OPEN"

  # u20: 대조군 idle
  Log "AM Inject done. (u20 intentionally idle)"

  SnapshotAll "D9 AM"
}

function PM() {
  Log "--- PM Inject (D9): 최소 유지 + 오답 1회만 추가 ---"

  # 12,13: JUST_OPEN만
  foreach ($u in 12,13) { Event $u "JUST_OPEN" }

  # u16: 복귀 유지
  Event 16 "JUST_OPEN"

  # u18/u19: 오답 각 1회씩만 (아침 신호가 DB에 들어갔는지 확인용)
  Event 18 $wrongType
  Event 19 $wrongType

  # u21: 1회 유지
  Event 21 "JUST_OPEN"

  Log "PM Inject done. (14/15/17/20 intentionally idle)"
}

function CLOSE() {
  Log "--- CLOSE (D9): 최종 스냅샷 + DB 검증 ---"
  SnapshotAll "D9 PM"
  DbVerifyToday
}

Log ("=== Day9 START phase={0} base={1} ===" -f $phase,$base)
Health

switch ($phase) {
  "am"    { AM }
  "pm"    { PM }
  "close" { CLOSE }
  "all"   { AM; PM; CLOSE }
}

Log ("=== Day9 END phase={0} ===" -f $phase)
Log ("LOG FILE => {0}" -f $logFile)