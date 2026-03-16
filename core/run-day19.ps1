param(
  [ValidateSet("sweep","close","all")]
  [string]$mode = "all",

  [string]$base = "http://127.0.0.1:8083",
  [string]$internalKey = "goosage-dev",

  [long[]]$userIds = @(5, 9, 10, 12),

  # 정공법: step별 독립 실험을 위해 기본 true
  [switch]$ResetHistory = $true,

  # step1 고활동 -> step4 저활동 (독립 실험)
  [int]$step1_jo = 2, [int]$step1_quiz = 8,
  [int]$step2_jo = 1, [int]$step2_quiz = 5,
  [int]$step3_jo = 1, [int]$step3_quiz = 2,
  [int]$step4_jo = 0, [int]$step4_quiz = 1,

  [string]$mysqlContainer = "goosage-mysql",
  [string]$dbName = "goosage",
  [string]$dbUser = "root",
  [string]$dbPass = "root123"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ok($m){ Write-Host "[OK]  $m" -ForegroundColor Green }
function Info($m){ Write-Host "[..]  $m" -ForegroundColor Cyan }
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
  $tmp = Join-Path $env:TEMP ("req.day19.{0}.{1}.json" -f $PID,(Get-Random))
  Write-Utf8NoBom $tmp $jsonBody
  $h=@()
  foreach($k in $headers.Keys){ $h += @("-H","${k}: $($headers[$k])") }
  $out = & curl.exe -sS -X POST $h -H "Content-Type: application/json" --data-binary "@$tmp" $url
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  return $out
}

function Wait-Server(){
  Info "WAIT server: $base/internal/ping"
  for($i=1; $i -le 60; $i++){
    try{
      $pong = Curl-Text "$base/internal/ping" @{ "X-INTERNAL-KEY" = $internalKey }
      if($pong -eq "pong"){
        Ok "ping=pong"
        return
      }
    } catch {}
    Start-Sleep -Seconds 1
  }
  Fail "server not ready"
}

function Db([string]$sql){
  $tmp = Join-Path $env:TEMP ("goosage_sql_day19_{0}_{1}.sql" -f $PID,(Get-Random))
  Write-Utf8NoBom $tmp $sql

  Get-Content $tmp -Raw | & docker exec -i $mysqlContainer mysql "-u$dbUser" "-p$dbPass" $dbName
  $exitCode = $LASTEXITCODE

  Remove-Item $tmp -Force -ErrorAction SilentlyContinue

  if($exitCode -ne 0){
    throw "Db failed (exitCode=$exitCode)"
  }
}

function Reset-HistoryFn([long]$uid){
  Info "RESET history (userId=$uid)"
  $sql = @"
DELETE FROM study_events WHERE user_id = $uid;
DELETE FROM daily_learning WHERE user_id = $uid;

SELECT COUNT(*) AS total_events
FROM study_events
WHERE user_id = $uid;
"@
  Db $sql | Out-Host
  Ok "history reset done (userId=$uid)"
}

function Post-Event([long]$uid,[string]$type){
  $json = ([ordered]@{ userId=$uid; type=$type } | ConvertTo-Json -Compress)
  $out = Curl-PostJson "$base/internal/study/events" $json @{ "X-INTERNAL-KEY" = $internalKey }
  if(-not $out){
    Fail "event post failed (userId=$uid, type=$type)"
  }
}

function Step-Config([int]$step){
  switch($step){
    1 { return @{ jo=$step1_jo; quiz=$step1_quiz } }
    2 { return @{ jo=$step2_jo; quiz=$step2_quiz } }
    3 { return @{ jo=$step3_jo; quiz=$step3_quiz } }
    4 { return @{ jo=$step4_jo; quiz=$step4_quiz } }
    default { throw "invalid step=$step" }
  }
}

function Seed-Step([long]$uid,[int]$step){
  $c = Step-Config $step
  Warn "---- USER $uid STEP $step ----"
  Info "config => JUST_OPEN=$($c.jo), QUIZ_SUBMIT=$($c.quiz)"

  if($ResetHistory -or $mode -eq "all" -or $mode -eq "sweep"){
    Reset-HistoryFn $uid
  }

  if($c.jo -gt 0){
    1..$c.jo | ForEach-Object { Post-Event $uid "JUST_OPEN" }
  }

  if($c.quiz -gt 0){
    1..$c.quiz | ForEach-Object { Post-Event $uid "QUIZ_SUBMIT" }
  }

  $checkSql = @"
SELECT DATE(created_at) AS dt, event_type, COUNT(*) AS cnt
FROM study_events
WHERE user_id = $uid
GROUP BY DATE(created_at), event_type
ORDER BY dt DESC, event_type;

SELECT *
FROM daily_learning
WHERE user_id = $uid
ORDER BY ymd DESC;
"@
  Db $checkSql | Out-Host
}

function Get-Coach([long]$uid){
  Curl-Text "$base/internal/study/coach?userId=$uid" @{ "X-INTERNAL-KEY" = $internalKey }
}

function Save-Coach([long]$uid,[string]$tag,[string]$json){
  $ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $dir = Join-Path $PSScriptRoot "artifacts"
  if(-not (Test-Path $dir)){ New-Item -ItemType Directory -Path $dir | Out-Null }
  $file = Join-Path $dir ("coach.day19.{0}.user{1}.{2}.json" -f $tag,$uid,$ts)
  Write-Utf8NoBom $file $json
  Ok "saved => $file"
}

Wait-Server
Warn "mode=$mode ResetHistory=$ResetHistory"
Warn "users=$($userIds -join ',')"

if($mode -eq "close"){
  foreach($uid in $userIds){
    $coach = Get-Coach $uid
    $coach | Out-Host
    Save-Coach $uid "close" $coach
  }
  Ok "DAY19 CLOSE DONE"
  exit 0
}

foreach($uid in $userIds){
  for($s=1; $s -le 4; $s++){
    Seed-Step $uid $s
    $coach = Get-Coach $uid
    $coach | Out-Host
    Save-Coach $uid ("s{0}" -f $s) $coach
  }
}

Ok "DAY19 DONE"