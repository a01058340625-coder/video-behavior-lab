param(
  [ValidateSet("seed","close","all")]
  [string]$mode = "all",

  [string]$base = "http://127.0.0.1:8083",
  [string]$internalKey = "goosage-dev",

  [long[]]$userIds = @(5, 9, 10, 12),

  # 유지 구간별 일자
  [int]$phase1DaysAgo = 4,
  [int]$phase2DaysAgo = 2,
  [int]$phase3DaysAgo = 0,

  # phase1: 오래전 최소 활동
  [int]$phase1JustOpen = 1,
  [int]$phase1Quiz = 1,

  # phase2: 중간 유지 활동
  [int]$phase2JustOpen = 1,
  [int]$phase2Quiz = 1,

  # phase3: 오늘 유지 활동
  [int]$phase3JustOpen = 1,
  [int]$phase3Quiz = 1,

  [switch]$ResetHistory = $true,

  [string]$mysqlContainer = "goosage-mysql",
  [string]$dbName = "goosage",
  [string]$dbUser = "root",
  [string]$dbPass = "root123"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ok($m){ Write-Host "[OK]  $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[!!]  $m" -ForegroundColor Yellow }
function Fail($m){ Write-Host "[FAIL] $m" -ForegroundColor Red; throw $m }

function Write-Utf8NoBom([string]$p,[string]$c){
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($p,$c,$enc)
}

function Curl-Text([string]$url,[hashtable]$headers=@{}){
  $h=@()
  foreach($k in $headers.Keys){ $h += @("-H","${k}: $($headers[$k])") }
  & curl.exe -sS $h $url
}

function Curl-PostJson([string]$url,[string]$jsonBody,[hashtable]$headers=@{}){
  $tmp = Join-Path $env:TEMP ("req.day25.{0}.{1}.json" -f $PID,(Get-Random))
  Write-Utf8NoBom $tmp $jsonBody

  try {
    $h=@()
    foreach($k in $headers.Keys){ $h += @("-H","${k}: $($headers[$k])") }
    $out = & curl.exe -sS -X POST $h -H "Content-Type: application/json" --data-binary "@$tmp" $url
    return $out
  }
  finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Db([string]$sql){
  $tmp = Join-Path $env:TEMP ("day25_sql_{0}_{1}.sql" -f $PID,(Get-Random))
  Write-Utf8NoBom $tmp $sql

  try {
    $cmd = "mysql -u{0} -p{1} {2}" -f $dbUser, $dbPass, $dbName
    Get-Content $tmp -Raw | docker exec -i $mysqlContainer sh -lc $cmd
  }
  finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Reset-History([long]$uid){
  Db @"
DELETE FROM study_events   WHERE user_id=$uid;
DELETE FROM daily_learning WHERE user_id=$uid;
SELECT COUNT(*) AS total_events FROM study_events WHERE user_id=$uid;
"@ | Out-Host
}

function Post-Event([long]$uid,[string]$type){
  $json = ([ordered]@{
    userId = $uid
    type   = $type
  } | ConvertTo-Json -Compress)

  $null = Curl-PostJson "$base/internal/study/events" $json @{ "X-INTERNAL-KEY" = $internalKey }
}

function Shift-Today([long]$uid,[int]$daysAgo){
  Db @"
START TRANSACTION;

UPDATE study_events
SET created_at = DATE_SUB(created_at, INTERVAL $daysAgo DAY)
WHERE user_id = $uid
  AND DATE(created_at) = CURDATE();

DELETE dl_today
FROM daily_learning dl_today
JOIN daily_learning dl_target
  ON dl_target.user_id = dl_today.user_id
 AND dl_target.ymd = DATE_SUB(dl_today.ymd, INTERVAL $daysAgo DAY)
WHERE dl_today.user_id = $uid
  AND dl_today.ymd = CURDATE();

UPDATE daily_learning
SET ymd = DATE_SUB(ymd, INTERVAL $daysAgo DAY)
WHERE user_id = $uid
  AND ymd = CURDATE();

COMMIT;

SELECT 'shift_done' AS status, $uid AS user_id, $daysAgo AS days_ago;
"@ | Out-Host
}

function Get-Coach([long]$uid){
  Curl-Text "$base/internal/study/coach?userId=$uid" @{ "X-INTERNAL-KEY" = $internalKey }
}

function Save-Coach([long]$uid,[string]$tag,[string]$json){
  $ts  = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $dir = Join-Path $PSScriptRoot "artifacts"

  if(-not (Test-Path $dir)){
    New-Item -ItemType Directory -Path $dir | Out-Null
  }

  $file = Join-Path $dir ("coach.day25.{0}.user{1}.{2}.json" -f $tag,$uid,$ts)
  Write-Utf8NoBom $file $json
  Ok "saved => $file"
}

function Seed-Phase([long]$uid,[int]$justOpen,[int]$quiz,[int]$daysAgo){
  if($justOpen -gt 0){
    1..$justOpen | ForEach-Object { Post-Event $uid "JUST_OPEN" }
  }

  if($quiz -gt 0){
    1..$quiz | ForEach-Object { Post-Event $uid "QUIZ_SUBMIT" }
  }

  if($daysAgo -gt 0){
    Shift-Today $uid $daysAgo
  }
}

foreach($uid in $userIds){

  Warn "=============================="
  Warn "DAY25 MAINTENANCE ALGORITHM TEST userId=$uid"
  Warn "=============================="

  if($ResetHistory){
    Reset-History $uid
  }

  # baseline: 완전 공백
  $baseline = Get-Coach $uid
  $baseline | Out-Host
  Save-Coach $uid "baseline" $baseline

  # phase1: 4일 전 최소 활동
  Seed-Phase $uid $phase1JustOpen $phase1Quiz $phase1DaysAgo
  $phase1 = Get-Coach $uid
  $phase1 | Out-Host
  Save-Coach $uid "phase1" $phase1

  # phase2: 2일 전 최소 활동
  Seed-Phase $uid $phase2JustOpen $phase2Quiz $phase2DaysAgo
  $phase2 = Get-Coach $uid
  $phase2 | Out-Host
  Save-Coach $uid "phase2" $phase2

  # phase3: 오늘 최소 활동
  Seed-Phase $uid $phase3JustOpen $phase3Quiz $phase3DaysAgo
  $phase3 = Get-Coach $uid
  $phase3 | Out-Host
  Save-Coach $uid "phase3" $phase3
}

Ok "DAY25 DONE"