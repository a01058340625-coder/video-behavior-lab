param(
  [ValidateSet("seed","close","all")]
  [string]$mode = "all",

  [string]$base = "http://127.0.0.1:8083",
  [string]$internalKey = "goosage-dev",

  [long[]]$userIds = @(5, 9, 10, 12),

  # userId=공백일수
  [string]$gapMap = "5=3,9=5,10=7,12=10",

  # 복귀 시 넣을 이벤트 수
  [int]$returnJustOpen = 1,
  [int]$returnQuiz = 2,

  [switch]$ResetHistory = $false,

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
  $tmp = Join-Path $env:TEMP ("req.day21.{0}.{1}.json" -f $PID,(Get-Random))
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
  $tmp = Join-Path $env:TEMP ("day21_sql_{0}_{1}.sql" -f $PID,(Get-Random))
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

-- 1) 오늘 생성된 이벤트를 과거로 이동
UPDATE study_events
SET created_at = DATE_SUB(created_at, INTERVAL $daysAgo DAY)
WHERE user_id = $uid
  AND DATE(created_at) = CURDATE();

-- 2) daily_learning 충돌 방지 처리
--    오늘 row를 target 날짜로 옮기려 할 때,
--    이미 같은 (user_id, target_ymd)가 있으면 오늘 row는 삭제
--    없으면 안전하게 update

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

  $file = Join-Path $dir ("coach.day21.{0}.user{1}.{2}.json" -f $tag,$uid,$ts)
  Write-Utf8NoBom $file $json
  Ok "saved => $file"
}

function Seed-Gap([long]$uid,[int]$gapDays){
  Warn "USER $uid gapDays=$gapDays"

  if($ResetHistory){
    Reset-History $uid
  }

  Post-Event $uid "JUST_OPEN"
  Post-Event $uid "QUIZ_SUBMIT"

  if($gapDays -gt 0){
    Shift-Today $uid $gapDays
  }
}

function Apply-Return([long]$uid){
  Warn "RETURN userId=$uid"

  if($returnJustOpen -gt 0){
    1..$returnJustOpen | ForEach-Object { Post-Event $uid "JUST_OPEN" }
  }

  if($returnQuiz -gt 0){
    1..$returnQuiz | ForEach-Object { Post-Event $uid "QUIZ_SUBMIT" }
  }
}

$map = Parse-Map $gapMap

foreach($uid in $userIds){

  $gap = 0
  if($map.ContainsKey($uid)){
    $gap = $map[$uid]
  }

  Seed-Gap $uid $gap

  $before = Get-Coach $uid
  $before | Out-Host
  Save-Coach $uid "beforeReturn" $before

  Apply-Return $uid

  $after = Get-Coach $uid
  $after | Out-Host
  Save-Coach $uid "afterReturn" $after
}

Ok "DAY21 DONE"