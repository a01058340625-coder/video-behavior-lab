param(
  [ValidateSet("seed","close","all")]
  [string]$mode = "all",

  [string]$base = "http://127.0.0.1:8083",
  [string]$internalKey = "goosage-dev",

  [long[]]$userIds = @(5, 9, 10, 12),

  # userId=공백일수
  [string]$gapMap = "5=3,9=5,10=7,12=10",

  # 전략 A: 가벼운 개입
  [int]$aJustOpen = 1,
  [int]$aQuiz = 1,
  [int]$aWrong = 0,

  # 전략 B: 강한 개입
  [int]$bJustOpen = 1,
  [int]$bQuiz = 3,
  [int]$bWrong = 1,

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
  $tmp = Join-Path $env:TEMP ("req.day22.{0}.{1}.json" -f $PID,(Get-Random))
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

function Parse-Map([string]$text){
  $m=@{}
  foreach($pair in ($text -split ",")){
    $p=$pair.Trim()
    if(-not $p){ continue }

    $kv=$p -split "=",2
    if($kv.Count -ne 2){ continue }

    $m[[long]$kv[0].Trim()] = [int]$kv[1].Trim()
  }
  return $m
}

function Db([string]$sql){
  $tmp = Join-Path $env:TEMP ("day22_sql_{0}_{1}.sql" -f $PID,(Get-Random))
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

  $file = Join-Path $dir ("coach.day22.{0}.user{1}.{2}.json" -f $tag,$uid,$ts)
  Write-Utf8NoBom $file $json
  Ok "saved => $file"
}

function Seed-Gap([long]$uid,[int]$gapDays){
  Warn "USER $uid gapDays=$gapDays baseline seed"

  if($ResetHistory){
    Reset-History $uid
  }

  # baseline: 예전 학습 흔적 2개
  Post-Event $uid "JUST_OPEN"
  Post-Event $uid "QUIZ_SUBMIT"

  if($gapDays -gt 0){
    Shift-Today $uid $gapDays
  }
}

function Apply-StrategyA([long]$uid){
  Warn "STRATEGY A userId=$uid"

  if($aJustOpen -gt 0){
    1..$aJustOpen | ForEach-Object { Post-Event $uid "JUST_OPEN" }
  }

  if($aQuiz -gt 0){
    1..$aQuiz | ForEach-Object { Post-Event $uid "QUIZ_SUBMIT" }
  }

  if($aWrong -gt 0){
    1..$aWrong | ForEach-Object { Post-Event $uid "REVIEW_WRONG" }
  }
}

function Apply-StrategyB([long]$uid){
  Warn "STRATEGY B userId=$uid"

  if($bJustOpen -gt 0){
    1..$bJustOpen | ForEach-Object { Post-Event $uid "JUST_OPEN" }
  }

  if($bQuiz -gt 0){
    1..$bQuiz | ForEach-Object { Post-Event $uid "QUIZ_SUBMIT" }
  }

  if($bWrong -gt 0){
    1..$bWrong | ForEach-Object { Post-Event $uid "REVIEW_WRONG" }
  }
}

$map = Parse-Map $gapMap

foreach($uid in $userIds){

  $gap = 0
  if($map.ContainsKey($uid)){
    $gap = $map[$uid]
  }

  Warn "=============================="
  Warn "DAY22 A/B TEST userId=$uid"
  Warn "=============================="

  # --------------------------
  # A 시나리오
  # --------------------------
  Seed-Gap $uid $gap

  $baseA = Get-Coach $uid
  $baseA | Out-Host
  Save-Coach $uid "baselineA" $baseA

  Apply-StrategyA $uid

  $afterA = Get-Coach $uid
  $afterA | Out-Host
  Save-Coach $uid "afterA" $afterA

  # --------------------------
  # B 시나리오 (동일 baseline 재구축)
  # --------------------------
  Seed-Gap $uid $gap

  $baseB = Get-Coach $uid
  $baseB | Out-Host
  Save-Coach $uid "baselineB" $baseB

  Apply-StrategyB $uid

  $afterB = Get-Coach $uid
  $afterB | Out-Host
  Save-Coach $uid "afterB" $afterB
}

Ok "DAY22 DONE"