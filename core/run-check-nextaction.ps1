param(
  [string]$base = "http://127.0.0.1:8083",
  [long]$userId = 5,
  [string]$internalKey = "goosage-dev",

  # docker container names
  [string]$apiContainer = "goosage-api",
  [string]$mysqlContainer = "goosage-mysql",
  [string]$dbName = "goosage",
  [string]$dbUser = "root",
  [string]$dbPass = "root123",

  # policy
  [int]$doneQuizMin = 5,

  # expected nextAction after REVIEW_WRONG (엔진 정책에 따라 다를 수 있음)
  [ValidateSet("REVIEW_WRONG_ONE","JUST_OPEN","TODAY_DONE","ANY")]
  [string]$ExpectedAfterReviewWrong = "ANY",

  # behavior toggle (현재 룰: JUST_OPEN 한 번만 해도 studiedToday=true → TODAY_DONE이 나올 수 있음)
  [switch]$ExpectTodayDoneOnJustOpen = $false,

  # safety: 리셋 없이 테스트하면 기존 데이터 때문에 결과가 달라질 수 있음
  [switch]$ResetToday = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ===== Encoding fix (PS5.1/PS7 공통: 콘솔/파워셸 출력 한글 깨짐 방지) =====
try { chcp 65001 | Out-Null } catch {}
try {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [Console]::InputEncoding  = $utf8NoBom
  [Console]::OutputEncoding = $utf8NoBom
  $OutputEncoding = $utf8NoBom
} catch {}

function Ok($msg)  { Write-Host "[OK]  $msg" -ForegroundColor Green }
function Info($msg){ Write-Host "[..]  $msg" -ForegroundColor Cyan }
function Warn($msg){ Write-Host "[!!]  $msg" -ForegroundColor Yellow }
function Fail($msg){ Write-Host "[FAIL] $msg" -ForegroundColor Red; throw $msg }

function Curl-Text([string]$url, [hashtable]$headers = @{}) {
  $h = @()
  foreach ($k in $headers.Keys) { $h += @("-H", "${k}: $($headers[$k])") }
  $out = & curl.exe -sS $h $url
  return $out
}

function Write-Utf8File-NoBom([string]$path, [string]$text) {
  # PS5.1에서도 확실하게 UTF-8(무BOM)로 쓰기
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $text, $enc)
}

function Curl-PostJson([string]$url, [string]$jsonBody, [hashtable]$headers = @{}) {
  $tmp = Join-Path $env:TEMP ("req.{0}.{1}.json" -f $PID, (Get-Random))

  # Set-Content -Encoding utf8BOM 은 PS5.1에서 없음 → 안전하게 .NET으로 작성
  Write-Utf8File-NoBom $tmp $jsonBody

  $h = @()
  foreach ($k in $headers.Keys) { $h += @("-H", "${k}: $($headers[$k])") }

  $out = & curl.exe -sS -X POST $h -H "Content-Type: application/json" --data-binary "@$tmp" $url
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  return $out
}

function Assert-Eq($name, $actual, $expected) {
  if ($actual -ne $expected) {
    Fail "$name expected=[$expected] actual=[$actual]"
  } else {
    Ok "$name = $expected"
  }
}

function Assert-NotNull($name, $val) {
  if ($null -eq $val -or ($val -is [string] -and [string]::IsNullOrWhiteSpace($val))) {
    Fail "$name is null/empty"
  } else {
    Ok "$name is present"
  }
}

function Wait-Ping() {
  Info "WAIT: server ready check (ping -> coach fallback)"

  for ($i=1; $i -le 60; $i++) {
    try {
      $pong = Curl-Text "$base/internal/ping"
      if ($pong -eq "pong") { Ok "ping=pong"; return }
    } catch {}

    try {
      $res = Curl-Text "$base/internal/study/coach?userId=$userId" @{ "X-INTERNAL-KEY" = $internalKey }
      if ($res -and $res.Length -gt 0) {
        Ok "coach endpoint responded (server ready)"
        return
      }
    } catch {}

    Start-Sleep -Seconds 1
  }

  Fail "server not ready. Try: curl $base/internal/ping  OR docker logs --tail 200 $apiContainer"
}

function Reset-TodayData() {
  Info "RESET today data for userId=$userId (study_events + daily_learning)"

  $sql = "DELETE FROM study_events WHERE user_id=$userId AND DATE(created_at)=CURDATE(); " +
         "DELETE FROM daily_learning WHERE user_id=$userId AND ymd=CURDATE(); " +
         "SELECT COUNT(*) AS cnt FROM study_events WHERE user_id=$userId AND DATE(created_at)=CURDATE();"

  $out = & docker exec $mysqlContainer sh -lc "mysql -u$dbUser -p$dbPass $dbName -e '$sql'"
  $out | Out-Host

  $check = & docker exec $mysqlContainer sh -lc "mysql -u$dbUser -p$dbPass $dbName -N -e 'select count(*) from study_events where user_id=$userId and date(created_at)=curdate();'"
  if ([int]$check -ne 0) { Fail "reset verify failed: study_events today count=$check" }

  Ok "reset done + verify OK"
}

function Post-Event([string]$type, [Nullable[long]]$knowledgeId = $null) {
  $body = [ordered]@{ userId = $userId; type = $type }
  if ($null -ne $knowledgeId) { $body.knowledgeId = $knowledgeId }
  $json = ($body | ConvertTo-Json -Compress)

  Info "EVENT: $type (knowledgeId=$knowledgeId)"

  $res = Curl-PostJson "$base/internal/study/events" $json @{ "X-INTERNAL-KEY" = $internalKey }
  $obj = $res | ConvertFrom-Json

  $hasSuccess = ($null -ne $obj) -and ($obj.PSObject.Properties.Name -contains 'success')
  if ($hasSuccess -and -not $obj.success) {
    throw "event failed: $res"
  }

  Ok "event ok"
}

function Get-Coach() {
  $res = Curl-Text "$base/internal/study/coach?userId=$userId" @{ "X-INTERNAL-KEY" = $internalKey }
  $obj = $res | ConvertFrom-Json

  $hasSuccess = ($null -ne $obj) -and ($obj.PSObject.Properties.Name -contains 'success')

  if ($hasSuccess) {
    if (-not $obj.success) {
      Fail "coach failed: $($obj.message)"
    }
    return $obj.data
  }

  return $obj
}

function Print-Coach($d) {
  $state = $d.state
  $next  = $d.nextAction
  $pred  = $d.prediction

  Write-Host ""
  Write-Host "=== COACH (userId=$userId) ===" -ForegroundColor White
  Write-Host ("state: events={0}, quiz={1}, wrong={2}" -f $state.eventsCount, $state.quizSubmits, $state.wrongReviews)
  Write-Host ("pred : level={0}, reason={1}, dataPoor={2}" -f $pred.level, $pred.reasonCode, $pred.dataPoor)
  Write-Host ("next : type={0}, label={1}" -f $next.type, $next.label)
  Write-Host ("next : reason={0}" -f $next.reason)

  if ($pred.reasonCode -eq "DEFAULT_FALLBACK") {
    Warn "prediction.reasonCode=DEFAULT_FALLBACK (rules may not be applied / fallback path)"
  }

  Write-Host ""
}

# =========================
# MAIN
# =========================
Wait-Ping

if ($ResetToday) { Reset-TodayData }
else { Warn "ResetToday is OFF. Existing data may affect expectations." }

# CASE 1) 오늘 이벤트 0 → JUST_OPEN
Info "CASE1: no events today => nextAction JUST_OPEN"
$d1 = Get-Coach
Print-Coach $d1
Assert-Eq "nextAction.type" $d1.nextAction.type "JUST_OPEN"

# CASE 2) JUST_OPEN 1발
Post-Event "JUST_OPEN" $null
$d2 = Get-Coach
Print-Coach $d2
if ($ExpectTodayDoneOnJustOpen) {
  Assert-Eq "nextAction.type(after JUST_OPEN)" $d2.nextAction.type "TODAY_DONE"
} else {
  Assert-Eq "nextAction.type(after JUST_OPEN)" $d2.nextAction.type "JUST_OPEN"
}

# CASE 3) REVIEW_WRONG 1발 (+knowledgeId)  ---- (오답 테스트 케이스)
Post-Event "REVIEW_WRONG" 1
$d3 = Get-Coach
Print-Coach $d3

if ($ExpectTodayDoneOnJustOpen) {
  Assert-Eq "nextAction.type(after REVIEW_WRONG)" $d3.nextAction.type "TODAY_DONE"
}
else {
  # 최소 검증: wrong 카운트 증가(핵심)
  if ($d3.state.wrongReviews -lt 1) {
    Fail "state.wrongReviews expected>=1 actual=[$($d3.state.wrongReviews)]"
  } else {
    Ok "state.wrongReviews >= 1"
  }

  if ($ExpectedAfterReviewWrong -ne "ANY") {
    Assert-Eq "nextAction.type(after REVIEW_WRONG)" $d3.nextAction.type $ExpectedAfterReviewWrong
  } else {
    Warn "skip strict nextAction check(after REVIEW_WRONG). actual=[$($d3.nextAction.type)] (policy varies)"
    if ($d3.nextAction.type -eq "REVIEW_WRONG_ONE") {
      Assert-NotNull "nextAction.knowledgeId" $d3.nextAction.knowledgeId
    }
  }
}

# CASE 4) TODAY_DONE 검증 케이스는 "wrong==0"이어야 함 (정책: quiz>=N && wrong==0)
Info "CASE4: TODAY_DONE scenario => reset again to guarantee wrong==0"
Reset-TodayData

# (정책상 TODAY_DONE은 wrong==0 조건이므로, 오답 없이 퀴즈만 채움)
Post-Event "JUST_OPEN" $null

for ($i=1; $i -le $doneQuizMin; $i++) { Post-Event "QUIZ_SUBMIT" $null }
$d4 = Get-Coach
Print-Coach $d4

Assert-Eq "prediction.reasonCode(after QUIZ>=min & wrong==0)" $d4.prediction.reasonCode "TODAY_DONE"
Assert-Eq "nextAction.type(after TODAY_DONE)" $d4.nextAction.type "TODAY_DONE"

Ok "ALL CHECKS PASSED"