param(
  [long[]]$userIds = @(31,32,33),

  [string]$mysqlContainer = "goosage-mysql",
  [string]$dbName = "goosage",
  [string]$dbUser = "root",
  [string]$dbPass = "root123"
)

chcp 65001 > $null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Utf8NoBom([string]$p,[string]$c){
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($p,$c,$enc)
}

function Db([string]$sql){
  $tmp = Join-Path $env:TEMP ("sql.verifypersona.{0}.sql" -f (Get-Random))
  Write-Utf8NoBom $tmp $sql

  try {
    docker cp $tmp "${mysqlContainer}:/tmp/verifypersona.sql" | Out-Null
    docker exec $mysqlContainer sh -lc "mysql -N -u$dbUser -p$dbPass $dbName < /tmp/verifypersona.sql"
  }
  finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    docker exec $mysqlContainer sh -lc "rm -f /tmp/verifypersona.sql" | Out-Null
  }
}

function Verify-User([long]$uid,[string]$label){
  Write-Host ""
  Write-Host "==============================" -ForegroundColor Yellow
  Write-Host "VERIFY $label user=$uid" -ForegroundColor Yellow
  Write-Host "==============================" -ForegroundColor Yellow

  Db @"
SELECT
  user_id,
  COUNT(*) AS events,
  COALESCE(SUM(type='JUST_OPEN'),0) AS opens,
  COALESCE(SUM(type='QUIZ_SUBMIT'),0) AS quiz,
  COALESCE(SUM(type='REVIEW_WRONG'),0) AS wrong,
  COALESCE(SUM(type='WRONG_REVIEW_DONE'),0) AS wrong_done,
  COUNT(DISTINCT DATE(created_at)) AS active_days,
  MIN(created_at) AS first_at,
  MAX(created_at) AS last_at
FROM study_events
WHERE user_id = $uid
GROUP BY user_id;
"@

  Db @"
SELECT
  DATE(created_at) AS ymd,
  COUNT(*) AS events,
  COALESCE(SUM(type='JUST_OPEN'),0) AS opens,
  COALESCE(SUM(type='QUIZ_SUBMIT'),0) AS quiz,
  COALESCE(SUM(type='REVIEW_WRONG'),0) AS wrong,
  COALESCE(SUM(type='WRONG_REVIEW_DONE'),0) AS wrong_done
FROM study_events
WHERE user_id = $uid
GROUP BY DATE(created_at)
ORDER BY ymd;
"@

  Db @"
SELECT
  id, user_id, type, created_at
FROM study_events
WHERE user_id = $uid
ORDER BY id;
"@
}

if($userIds.Length -lt 3){
  throw "userIds must contain 3 ids. ex) 31,32,33"
}

Verify-User $userIds[0] "IMMERSED"
Verify-User $userIds[1] "GAP"
Verify-User $userIds[2] "WRONGPERSONA"

Write-Host ""
Write-Host "==============================" -ForegroundColor Green
Write-Host "CHECKPOINT" -ForegroundColor Green
Write-Host "==============================" -ForegroundColor Green
Write-Host "1. IMMERSED     : active_days >= 3, quiz 누적 존재, wrong_done 존재"
Write-Host "2. GAP          : row 0 또는 출력 없음"
Write-Host "3. WRONGPERSONA : quiz >= 5, wrong > 0, wrong_done = 0"
Write-Host "4. WRONGPERSONA : 날짜가 어제/오늘로 섞이면 정상"