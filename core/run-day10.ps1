param(
  [ValidateSet("am","pm","close","all")]
  [string]$phase = "all",

  [string]$base = "http://127.0.0.1:8083",
  [string]$internalKey = "goosage-dev",

  # 세션 로그인 (coach 조회용) - 현재 런타임에서는 401(BasicAuth)일 수 있어 기본 OFF 권장
  [string]$email = "u16@goosage.test",
  [string]$password = "1234",
  [string]$cookieFile = ".\cookie.day10.txt",

  # coach 조회를 끄는 스위치 (기본: OFF)
  [switch]$NoCoach = $true,

  # target user
  [int]$userId = 5,

  # DB (docker mysql)
  [string]$dbName = "goosage",
  [string]$dbRootPass = "root123",

  # 로그/스냅샷 저장
  [string]$artDir = ".\artifacts"
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

function Health(){
  $h = curl.exe -sS "$base/health"
  if ($h -match '"status"\s*:\s*"UP"' -or $h -match '"UP"') { Ok "HEALTH UP" }
  else { Warn "HEALTH unexpected body: $h" }
}

# Login은 coach용. 현재 /auth/login이 401(BasicAuth)면 실패할 수 있음.
# 실패해도 운영(이벤트 주입 + DB 증거)은 계속 가능하도록 설계.
function Login(){
  if (Test-Path $cookieFile) { Remove-Item $cookieFile -Force }

  $loginFile = Join-Path $artDir ("login.day10.{0}.json" -f (TS))
  $loginOut  = Join-Path $artDir ("login.day10.{0}.out.txt" -f (TS))

  @{ email = $email; password = $password } |
    ConvertTo-Json -Compress |
    Set-Content -Encoding ascii $loginFile

  $raw = curl.exe -i -sS -c $cookieFile -X POST "$base/auth/login" `
    -H "Content-Type: application/json" `
    --data-binary "@$loginFile"

  $raw | Set-Content -Encoding utf8 $loginOut

  if ($raw -match '"success"\s*:\s*true') {
    Ok "LOGIN OK (cookie: $cookieFile)"
    return $true
  }

  Warn "LOGIN FAIL (see $loginOut)"
  return $false
}

function Coach($tag){
  $out = Join-Path $artDir ("coach.day10.{0}.{1}.json" -f $tag, (TS))
  $body = curl.exe -sS -b $cookieFile "$base/study/coach?userId=$userId"
  $body | Set-Content -Encoding utf8 $out
  Ok "COACH $tag saved => $out"
  return $body
}

function InternalEventFromFile($jsonPath){
  $resp = curl.exe -sS -X POST "$base/internal/study/events" `
    -H "Content-Type: application/json" `
    -H "X-INTERNAL-KEY: $internalKey" `
    --data-binary "@$jsonPath"

  if ($resp -match '"success"\s*:\s*true') { return $true }
  Warn "EVENT unexpected: $resp"
  return $false
}

function MakeEventFile($type){
  $p = Join-Path $artDir ("event.day10.{0}.{1}.json" -f $type, (TS))
  @{ userId = $userId; type = $type } |
    ConvertTo-Json -Compress |
    Set-Content -Encoding ascii $p
  return $p
}

function InjectMany($type, $n){
  for ($i=1; $i -le $n; $i++){
    $f = MakeEventFile $type
    $ok = InternalEventFromFile $f
    if ($ok) { Log "EVENT OK  $type ($i/$n)" } else { throw "EVENT FAIL $type ($i/$n)" }
    Start-Sleep -Milliseconds 200
  }
}

function DbCountsToday(){
  $q = @"
select user_id,type,count(*) cnt
from study_events
where date(created_at)=curdate()
group by user_id,type
order by user_id,type;
"@
  docker exec goosage-mysql mysql -uroot "-p$dbRootPass" $dbName -e "$q"
}

function DailyLearningToday(){
  $q = @"
select user_id,ymd,events_count,quiz_submits,wrong_reviews,last_event_at
from daily_learning
where user_id=$userId and ymd=curdate();
"@
  docker exec goosage-mysql mysql -uroot "-p$dbRootPass" $dbName -e "$q"
}

function TryCoach($tag){
  if ($NoCoach) {
    Warn "SKIP COACH($tag) (NoCoach=true)"
    return
  }
  $loggedIn = Login
  if ($loggedIn) { Coach $tag }
  else { Warn "SKIP COACH($tag) due to login fail" }
}

function Phase-AM(){
  Log "=== DAY10 AM START (userId=$userId) ==="
  Health

  TryCoach "before.am"

  # Day10 AM 패턴(기본): OPEN 1 + QUIZ 1
  InjectMany "JUST_OPEN" 1
  InjectMany "QUIZ_SUBMIT" 1

  TryCoach "after.am"

  Log "=== DAY10 AM END ==="
}

function Phase-PM(){
  Log "=== DAY10 PM START (userId=$userId) ==="
  Health

  TryCoach "before.pm"

  # Day10 PM 패턴(기본): OPEN 1 + QUIZ 2 + WRONG 1
  InjectMany "JUST_OPEN" 1
  InjectMany "QUIZ_SUBMIT" 2
  InjectMany "REVIEW_WRONG" 1

  TryCoach "after.pm"

  Log "=== DAY10 PM END ==="
}

function Phase-CLOSE(){
  Log "=== DAY10 CLOSE START (userId=$userId) ==="
  Health

  Log "--- DB COUNT (today) ---"
  (DbCountsToday) | Write-Host

  Log "--- DAILY_LEARNING (today, user) ---"
  (DailyLearningToday) | Write-Host

  Log "=== DAY10 CLOSE END ==="
}

# ---- main ----
Ensure-Dir $artDir

switch ($phase) {
  "am"    { Phase-AM }
  "pm"    { Phase-PM }
  "close" { Phase-CLOSE }
  "all"   { Phase-AM; Phase-PM; Phase-CLOSE }
}