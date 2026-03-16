# C:\dev\loosegoose\goosage-scripts\run-day6.ps1
param(
  [ValidateSet("am","pm","close","all")]
  [string]$phase = "all",

  [string]$base = "http://127.0.0.1:8084",

  # docker mysql (권장: close 단계 DB 카운트는 docker exec로 고정)
  [string]$dbName = "goosage_local",
 [string]$dbRootPass = "root",

  [string]$logDir = ".\artifacts"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ts = Get-Date -Format "yyyyMMdd-HHmmss"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ("day6.{0}.{1}.log" -f $phase,$ts)

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
  $sql = "select user_id, count(*) cnt from study_events where date(created_at)=curdate() group by user_id order by user_id;"
  docker exec -it goosage-mysql mysql -uroot -p$dbRootPass $dbName -e $sql | ForEach-Object { Log $_ }
}

function AM() {
  Log "--- AM Inject: WARNING 분기 실험 (D6) ---"

  # A) 몰입 유지 (12,13)
  foreach ($u in 12,13) {
    Event $u "JUST_OPEN"
    Start-Sleep -Seconds 10
    Event $u "QUIZ_SUBMIT"
  }

  # B) 유지형 (14,15)
  foreach ($u in 14,15) { Event $u "JUST_OPEN" }

  # C) 핵심(16~18)
  # 16: 공백 유지
  Event 17 "JUST_OPEN"
  Event 18 "QUIZ_SUBMIT"

  # D) 오답형 (19)
  1..2 | ForEach-Object { Event 19 "REVIEW_WRONG" }

  # 20,21: 공백 유지
  Log "AM Inject done. (16/20/21 intentionally idle)"

  SnapshotAll "D6 AM"
}

function PM() {
  Log "--- PM Inject: 번아웃/복귀 확인 (D6) ---"

  # 12,13 한 번만(과몰입 방지)
  foreach ($u in 12,13) { Event $u "JUST_OPEN" }

  # 17 유지
  Event 17 "JUST_OPEN"

  # 18: 공백 유지
  # 14,15: 공백 유지
  # 16,20,21: 공백 유지
  # 19: 공백 유지
  Log "PM Inject done. (18/14/15/16/19/20/21 intentionally idle)"
}

function CLOSE() {
  Log "--- CLOSE: 오늘 최종 스냅샷 + DB 카운트 (D6) ---"
  SnapshotAll "D6 PM"
  DbCountToday
}

Log ("=== Day6 START phase={0} base={1} ===" -f $phase,$base)
Health

switch ($phase) {
  "am"    { AM }
  "pm"    { PM }
  "close" { CLOSE }
  "all"   { AM; PM; CLOSE }
}

Log ("=== Day6 END phase={0} ===" -f $phase)
Log ("LOG FILE => {0}" -f $logFile)