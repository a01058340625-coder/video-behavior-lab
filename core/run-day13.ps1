# C:\dev\loosegoose\goosage-scripts\run-day13.ps1
param(
  [ValidateSet("am","pm","close","all")]
  [string]$phase = "all",

  [string]$base = "http://127.0.0.1:8083",
  [string]$internalKey = "goosage-dev",

  # Day13: 유저별 시나리오 다양화 (기본 4명)
  [long[]]$userIds = @(5, 9, 10, 12),

  # 유저별 preset 매핑 (문자열: "userId=preset,userId=preset,...")
  # preset: expand/safe/wrong/low/streak
  # 예) -scenarioMap "5=wrong,9=safe,10=low,12=expand"
  [string]$scenarioMap = "5=expand,9=safe,10=low,12=wrong",

  [switch]$ResetToday = $false,

  # 공통 파라미터(필요시 조정)
  [long]$wrongKnowledgeId = 1,

  # expand 기본(AM/PM)
  [int]$amJustOpen = 1,
  [int]$amQuiz = 2,
  [int]$amWrong = 0,

  [int]$pmJustOpen = 1,
  [int]$pmQuiz = 5,
  [int]$pmWrong = 2,

  # DB 컨테이너/계정
  [string]$mysqlContainer = "goosage-mysql",
  [string]$dbName = "goosage",
  [string]$dbUser = "root",
  [string]$dbPass = "root123"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ok($msg){ Write-Host "[OK]  $msg" -ForegroundColor Green }
function Info($msg){ Write-Host "[..]  $msg" -ForegroundColor Cyan }
function Warn($msg){ Write-Host "[!!]  $msg" -ForegroundColor Yellow }
function Fail($msg){ Write-Host "[FAIL] $msg" -ForegroundColor Red; throw $msg }

function Write-Utf8NoBom([string]$path, [string]$content) {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

function Curl-Text([string]$url, [hashtable]$headers = @{}) {
  $h = @()
  foreach ($k in $headers.Keys) { $h += @("-H", "${k}: $($headers[$k])") }
  return (& curl.exe -sS $h $url)
}

function Curl-PostJson([string]$url, [string]$jsonBody, [hashtable]$headers = @{}) {
  $tmp = Join-Path $env:TEMP ("req.day13.{0}.{1}.json" -f $PID, (Get-Random))
  Write-Utf8NoBom $tmp $jsonBody

  $h = @()
  foreach ($k in $headers.Keys) { $h += @("-H", "${k}: $($headers[$k])") }

  $out = & curl.exe -sS -X POST $h -H "Content-Type: application/json" --data-binary "@$tmp" $url
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  return $out
}

function Wait-Server() {
  Info "WAIT server: $base/internal/ping"
  for ($i=1; $i -le 60; $i++) {
    try {
      $pong = Curl-Text "$base/internal/ping" @{ "X-INTERNAL-KEY" = $internalKey }
      if ($pong -eq "pong") { Ok "ping=pong"; return }
    } catch {}
    Start-Sleep -Seconds 1
  }
  Fail "server not ready"
}

function Reset-TodayData([long]$uid) {
  Info "RESET today data (userId=$uid)"
  $sql = "DELETE FROM study_events WHERE user_id=$uid AND DATE(created_at)=CURDATE(); " +
         "DELETE FROM daily_learning WHERE user_id=$uid AND ymd=CURDATE(); " +
         "SELECT COUNT(*) AS cnt FROM study_events WHERE user_id=$uid AND DATE(created_at)=CURDATE();"
  & docker exec $mysqlContainer sh -lc "mysql -u$dbUser -p$dbPass $dbName -e '$sql'" | Out-Host
  Ok "reset done (userId=$uid)"
}

function Post-Event([long]$uid, [string]$type, [Nullable[long]]$knowledgeId = $null) {
  $body = [ordered]@{ userId = $uid; type = $type }
  if ($null -ne $knowledgeId) { $body.knowledgeId = $knowledgeId }
  $json = ($body | ConvertTo-Json -Compress)

  Info "EVENT u$uid $type (knowledgeId=$knowledgeId)"
  $res = Curl-PostJson "$base/internal/study/events" $json @{ "X-INTERNAL-KEY" = $internalKey }
  if (-not $res) { Warn "empty response" } else { Ok "event ok" }
}

function Get-CoachJson([long]$uid) {
  return Curl-Text "$base/internal/study/coach?userId=$uid" @{ "X-INTERNAL-KEY" = $internalKey }
}

function Save-Coach([long]$uid, [string]$phaseTag, [string]$preset, [string]$json) {
  $ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $outDir = Join-Path $PSScriptRoot "artifacts"
  if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
  $outFile = Join-Path $outDir ("coach.day13.{0}.u{1}.{2}.{3}.json" -f $phaseTag, $uid, $preset, $ts)
  Write-Utf8NoBom $outFile $json
  Ok "coach saved => $outFile"
}

function Print-DbCounts([long]$uid) {
  Info "DB COUNT (today) userId=$uid"
  & docker exec $mysqlContainer sh -lc "mysql -u$dbUser -p$dbPass $dbName -e 'SELECT type, COUNT(*) cnt FROM study_events WHERE user_id=$uid AND DATE(created_at)=CURDATE() GROUP BY type ORDER BY type;'" | Out-Host
  & docker exec $mysqlContainer sh -lc "mysql -u$dbUser -p$dbPass $dbName -e 'SELECT * FROM daily_learning WHERE user_id=$uid AND ymd=CURDATE();'" | Out-Host
}

function Apply-Preset([string]$preset, [string]$when) {
  switch ($preset) {
    "safe" {
      if ($when -eq "am") { return @{ justOpen=1; quiz=3; wrong=0 } }
      else { return @{ justOpen=1; quiz=7; wrong=0 } }
    }
    "wrong" {
      if ($when -eq "am") { return @{ justOpen=1; quiz=1; wrong=3 } }
      else { return @{ justOpen=1; quiz=3; wrong=7 } }
    }
    "low" {
      if ($when -eq "am") { return @{ justOpen=1; quiz=0; wrong=0 } }
      else { return @{ justOpen=0; quiz=1; wrong=0 } }
    }
    "streak" {
      return @{ justOpen=1; quiz=0; wrong=0 }
    }
    default { # expand
      if ($when -eq "am") { return @{ justOpen=$amJustOpen; quiz=$amQuiz; wrong=$amWrong } }
      else { return @{ justOpen=$pmJustOpen; quiz=$pmQuiz; wrong=$pmWrong } }
    }
  }
}

function Parse-ScenarioMap([string]$mapText) {
  $m = @{}
  foreach ($pair in ($mapText -split ",")) {
    $p = $pair.Trim()
    if (-not $p) { continue }
    $kv = $p -split "=", 2
    if ($kv.Count -ne 2) { continue }
    $uid = [long]($kv[0].Trim())
    $preset = $kv[1].Trim().ToLower()
    $m[$uid] = $preset
  }
  return $m
}

function Run-Phase([string]$when, [hashtable]$map) {
  Warn "PHASE=$when ResetToday=$($ResetToday.IsPresent)"
  Warn "scenarioMap=$scenarioMap"

  foreach ($uid in $userIds) {
    $presetForUser = "expand"
    if ($map.ContainsKey($uid)) { $presetForUser = $map[$uid] }

    $counts = Apply-Preset $presetForUser $when
    $jo = [int]$counts.justOpen
    $qz = [int]$counts.quiz
    $wr = [int]$counts.wrong

    Warn "---- USER $uid preset=$presetForUser (justOpen=$jo quiz=$qz wrong=$wr) ----"

    if ($ResetToday) { Reset-TodayData $uid }

    if ($jo -gt 0) { 1..$jo | ForEach-Object { Post-Event $uid "JUST_OPEN" $null } }
    if ($wr -gt 0) { 1..$wr | ForEach-Object { Post-Event $uid "REVIEW_WRONG" $wrongKnowledgeId } }
    if ($qz -gt 0) { 1..$qz | ForEach-Object { Post-Event $uid "QUIZ_SUBMIT" $null } }

    $coachJson = Get-CoachJson $uid
    $coachJson | Out-Host
    Save-Coach $uid $when $presetForUser $coachJson
    Print-DbCounts $uid
  }
}

function Run-Close([hashtable]$map) {
  Warn "PHASE=close (증거/집계만 확인)"
  foreach ($uid in $userIds) {
    $presetForUser = "expand"
    if ($map.ContainsKey($uid)) { $presetForUser = $map[$uid] }

    Warn "---- USER $uid preset=$presetForUser ----"
    $coachJson = Get-CoachJson $uid
    $coachJson | Out-Host
    Save-Coach $uid "close" $presetForUser $coachJson
    Print-DbCounts $uid
  }
}

# =========================
# MAIN
# =========================
Wait-Server
if ($ResetToday) { Warn "ResetToday=ON (오늘치 초기화)" } else { Warn "ResetToday=OFF (누적)" }

$map = Parse-ScenarioMap $scenarioMap

switch ($phase) {
  "am"   { Run-Phase "am" $map }
  "pm"   { Run-Phase "pm" $map }
  "close"{ Run-Close $map }
  "all"  { Run-Phase "am" $map; Run-Phase "pm" $map; Run-Close $map }
}

Ok "DAY13 DONE"