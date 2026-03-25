param(
  [ValidateSet("seed","close","all")]
  [string]$mode = "all",

  [string]$base = "http://127.0.0.1:8084",
  [string]$internalKey = "goosage-dev",

  [long]$blankUser = 5,
  [long]$comebackUser = 9,
  [long]$steadyUser = 10,
  [long]$wrongHeavyUser = 12,
  [long]$recoveryUser = 13,
  [long]$anomalyUser = 14,

  [switch]$ResetHistory = $true,

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

function Ok($m){ Write-Host "[OK]  $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[!!]  $m" -ForegroundColor Yellow }
function Fail($m){ Write-Host "[FAIL] $m" -ForegroundColor Red; throw $m }

function Write-Utf8NoBom([string]$p,[string]$c){
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($p,$c,$enc)
}

function Curl-Text([string]$url,[hashtable]$headers=@{}){
  $h = @()
  foreach($k in $headers.Keys){
    $h += @("-H","${k}: $($headers[$k])")
  }
  & curl.exe -sS $h $url
}

function Curl-PostJson([string]$url,[string]$jsonBody,[hashtable]$headers=@{}){
  $tmp = Join-Path $env:TEMP ("req.day30.{0}.{1}.json" -f $PID,(Get-Random))
  Write-Utf8NoBom $tmp $jsonBody

  try {
    $h = @()
    foreach($k in $headers.Keys){
      $h += @("-H","${k}: $($headers[$k])")
    }
    & curl.exe -sS -X POST $h -H "Content-Type: application/json" --data-binary "@$tmp" $url
  }
  finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Db([string]$sql){
  $tmp = Join-Path $env:TEMP ("day30_sql_{0}_{1}.sql" -f $PID,(Get-Random))
  Write-Utf8NoBom $tmp $sql

  try {
    docker cp $tmp "${mysqlContainer}:/tmp/day30.sql" | Out-Null
    docker exec $mysqlContainer sh -lc "mysql -N -u$dbUser -p$dbPass $dbName < /tmp/day30.sql"
  }
  finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    docker exec $mysqlContainer sh -lc "rm -f /tmp/day30.sql" | Out-Null
  }
}

function Reset-History([long]$uid){
  Db @"
DELETE FROM study_events   WHERE user_id=$uid;
DELETE FROM daily_learning WHERE user_id=$uid;
"@ | Out-Null
}

function Post-Event([long]$uid,[string]$type){
  $json = ([ordered]@{
    userId = $uid
    type   = $type
  } | ConvertTo-Json -Compress)

  $null = Curl-PostJson "$base/internal/study/events" $json @{ "X-INTERNAL-KEY" = $internalKey }
}

function Shift-Today([long]$uid,[int]$daysAgo){
  if($daysAgo -le 0){ return }

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
"@ | Out-Null
}

function Get-Coach([long]$uid){
  Curl-Text "$base/internal/study/coach?userId=$uid" @{ "X-INTERNAL-KEY" = $internalKey } | ConvertFrom-Json
}

function Get-RawSummary([long]$uid){
  $raw = Db @"
SELECT
  COUNT(*) AS total_events,
  COALESCE(SUM(type='JUST_OPEN'),0) AS opens,
  COALESCE(SUM(type='QUIZ_SUBMIT'),0) AS quiz,
  COALESCE(SUM(type='REVIEW_WRONG'),0) AS wrongs,
  COALESCE(SUM(type='WRONG_REVIEW_DONE'),0) AS wrong_done,
  COUNT(DISTINCT DATE(created_at)) AS active_days,
  MIN(DATE(created_at)) AS first_day,
  MAX(DATE(created_at)) AS last_day
FROM study_events
WHERE user_id = $uid;
"@

  $cols = @()
  if($null -ne $raw){
    $cols = @($raw -split '\s+')
  }

  return [pscustomobject]@{
    total_events = if($cols.Length -ge 1){ [int]$cols[0] } else { 0 }
    opens        = if($cols.Length -ge 2){ [int]$cols[1] } else { 0 }
    quiz         = if($cols.Length -ge 3){ [int]$cols[2] } else { 0 }
    wrong        = if($cols.Length -ge 4){ [int]$cols[3] } else { 0 }
    wrong_done   = if($cols.Length -ge 5){ [int]$cols[4] } else { 0 }
    active_days  = if($cols.Length -ge 6){ [int]$cols[5] } else { 0 }
    first_day    = if($cols.Length -ge 7){ $cols[6] } else { $null }
    last_day     = if($cols.Length -ge 8){ $cols[7] } else { $null }
  }
}

function Get-Ratios([object]$raw){
  $total = [double]([Math]::Max(1, $raw.total_events))
  return [pscustomobject]@{
    open_ratio  = [math]::Round(($raw.opens / $total), 2)
    quiz_ratio  = [math]::Round(($raw.quiz / $total), 2)
    wrong_ratio = [math]::Round(($raw.wrong / $total), 2)
    done_ratio  = [math]::Round(($raw.wrong_done / $total), 2)
  }
}

function Save-Coach([long]$uid,[string]$tag,[object]$obj){
  $ts  = (Get-Date).ToString("yyyyMMdd-HHmmssfff")
  $dir = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) "core") "artifacts"

  if(-not (Test-Path $dir)){
    New-Item -ItemType Directory -Path $dir | Out-Null
  }

  $file = Join-Path $dir ("coach.day30.{0}.user{1}.{2}.json" -f $tag,$uid,$ts)
  ($obj | ConvertTo-Json -Depth 20) | Out-File $file -Encoding utf8
  Ok "saved => $file"
}

function Get-PropValue($obj,[string]$name,$default=$null){
  if($null -eq $obj){ return $default }
  $p = $obj.PSObject.Properties[$name]
  if($null -eq $p){ return $default }
  if($null -eq $p.Value){ return $default }
  return $p.Value
}

function Print-CoachSummary([long]$uid,[string]$tag,[object]$coach,[object]$raw,[object]$ratio){
  $p = $coach.prediction
  $e = if($p){ $p.evidence } else { $null }
  $s = $coach.state

  $level      = Get-PropValue $p "level" "-"
  $reasonCode = Get-PropValue $p "reasonCode" "-"
  $nextAction = Get-PropValue $coach "nextAction" "-"
  $daysSince  = Get-PropValue $e "daysSinceLastEvent" "-"
  $recent3d   = Get-PropValue $e "recentEventCount3d" "-"
  $streakDays = Get-PropValue $e "streakDays" "-"
  $eventsCnt  = Get-PropValue $s "eventsCount" 0
  $quizCnt    = Get-PropValue $s "quizSubmits" 0
  $wrongCnt   = Get-PropValue $s "wrongReviews" 0
  $wrongDone = Get-PropValue $s "wrongReviewDoneCount" 0

  Write-Host ""
  Write-Host "[SCENARIO] $tag user=$uid" -ForegroundColor Cyan
  Write-Host (" level={0} reason={1} action={2}" -f $level,$reasonCode,$nextAction)
  Write-Host (" evidence: daysSince={0} recent3d={1} streak={2}" -f $daysSince,$recent3d,$streakDays)
  Write-Host (" state:    events={0} quiz={1} wrong={2} wrongDone={3}" -f $eventsCnt,$quizCnt,$wrongCnt,$wrongDone)
  Write-Host (" raw:      total={0} opens={1} quiz={2} wrong={3} wrongDone={4} activeDays={5}" -f `
    $raw.total_events,$raw.opens,$raw.quiz,$raw.wrong,$raw.wrong_done,$raw.active_days)
  Write-Host (" ratio:    open={0} quiz={1} wrong={2} done={3}" -f `
    $ratio.open_ratio,$ratio.quiz_ratio,$ratio.wrong_ratio,$ratio.done_ratio)
  Write-Host (" range:    first={0} last={1}" -f $raw.first_day,$raw.last_day)
}

function Seed-Phase(
  [long]$uid,
  [int]$open,
  [int]$quiz,
  [int]$wrong,
  [int]$wrongDone,
  [int]$daysAgo
){
  if($open -gt 0){
    1..$open | ForEach-Object { Post-Event $uid "JUST_OPEN" }
  }

  if($quiz -gt 0){
    1..$quiz | ForEach-Object { Post-Event $uid "QUIZ_SUBMIT" }
  }

  if($wrong -gt 0){
    1..$wrong | ForEach-Object { Post-Event $uid "REVIEW_WRONG" }
  }

  if($wrongDone -gt 0){
    1..$wrongDone | ForEach-Object { Post-Event $uid "WRONG_REVIEW_DONE" }
  }

  if($daysAgo -gt 0){
    Shift-Today $uid $daysAgo
  }
}

$scenarios = @(
  [pscustomobject]@{
    userId = $blankUser
    tag    = "blank"
    title  = "BLANK"
    phases = @()
  },
  [pscustomobject]@{
    userId = $comebackUser
    tag    = "comeback"
    title  = "COMEBACK"
    phases = @(
      @{ open = 1; quiz = 0; wrong = 0; wrongDone = 0; daysAgo = 4 },
      @{ open = 1; quiz = 1; wrong = 0; wrongDone = 0; daysAgo = 0 }
    )
  },
  [pscustomobject]@{
    userId = $steadyUser
    tag    = "steady"
    title  = "STEADY"
    phases = @(
      @{ open = 1; quiz = 1; wrong = 0; wrongDone = 0; daysAgo = 2 },
      @{ open = 1; quiz = 2; wrong = 0; wrongDone = 0; daysAgo = 1 },
      @{ open = 1; quiz = 3; wrong = 0; wrongDone = 0; daysAgo = 0 }
    )
  },
  [pscustomobject]@{
    userId = $wrongHeavyUser
    tag    = "wrongheavy"
    title  = "WRONG_HEAVY"
    phases = @(
      @{ open = 1; quiz = 1; wrong = 3; wrongDone = 0; daysAgo = 1 },
      @{ open = 1; quiz = 1; wrong = 5; wrongDone = 1; daysAgo = 0 }
    )
  },
  [pscustomobject]@{
    userId = $recoveryUser
    tag    = "recovery"
    title  = "RECOVERY"
    phases = @(
      @{ open = 1; quiz = 1; wrong = 3; wrongDone = 0; daysAgo = 1 },
      @{ open = 1; quiz = 1; wrong = 1; wrongDone = 4; daysAgo = 0 }
    )
  },
  [pscustomobject]@{
    userId = $anomalyUser
    tag    = "anomaly"
    title  = "ANOMALY"
    phases = @(
      @{ open = 8;  quiz = 0; wrong = 0; wrongDone = 0; daysAgo = 1 },
      @{ open = 10; quiz = 0; wrong = 0; wrongDone = 0; daysAgo = 0 }
    )
  }
)

foreach($s in $scenarios){

  $uid   = [long]$s.userId
  $tag   = [string]$s.tag
  $title = [string]$s.title

  Warn "=============================="
  Warn "DAY30 ENGINE STABILITY $title userId=$uid"
  Warn "=============================="

  if($ResetHistory){
    Reset-History $uid
  }

  if($mode -in @("seed","all")){
    foreach($phase in $s.phases){
      Seed-Phase `
        $uid `
        ([int]$phase.open) `
        ([int]$phase.quiz) `
        ([int]$phase.wrong) `
        ([int]$phase.wrongDone) `
        ([int]$phase.daysAgo)
    }
  }

  if($mode -in @("close","all")){
    $coach = Get-Coach $uid
    $raw   = Get-RawSummary $uid
    $ratio = Get-Ratios $raw

    Print-CoachSummary $uid $tag $coach $raw $ratio

    $payload = [pscustomobject]@{
      day = 30
      tag = $tag
      userId = $uid
      coach = $coach
      raw = $raw
      ratio = $ratio
    }

    Save-Coach $uid $tag $payload
  }
}

Ok "DAY30 TUNED DONE"