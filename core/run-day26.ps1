param(
  [long[]]$userIds = @(5,9,10,12),

  [string]$base = "http://127.0.0.1:8083",
  [string]$internalKey = "goosage-dev",

  [string]$mysqlContainer = "goosage-mysql",
  [string]$dbName = "goosage",
  [string]$dbUser = "root",
  [string]$dbPass = "root123"
)

# UTF-8 인코딩
chcp 65001 > $null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Utf8NoBom([string]$p,[string]$c){
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($p,$c,$enc)
}

function Curl-Text([string]$url){
  & curl.exe -sS -H "X-INTERNAL-KEY: $internalKey" $url
}

function Curl-PostJson([string]$url,[string]$json){
  $tmp = Join-Path $env:TEMP ("req.{0}.json" -f (Get-Random))
  Write-Utf8NoBom $tmp $json

  try {
    & curl.exe -sS -X POST `
      -H "X-INTERNAL-KEY: $internalKey" `
      -H "Content-Type: application/json" `
      --data-binary "@$tmp" $url
  }
  finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Db($sql){
  $tmp = Join-Path $env:TEMP ("sql_{0}.sql" -f (Get-Random))
  Write-Utf8NoBom $tmp $sql

  try {
    $cmd = "mysql -N -u{0} -p{1} {2}" -f $dbUser,$dbPass,$dbName
    Get-Content $tmp -Raw | docker exec -i $mysqlContainer sh -lc $cmd
  }
  finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Reset-History($uid){
  Db @"
DELETE FROM study_events WHERE user_id=$uid;
DELETE FROM daily_learning WHERE user_id=$uid;
"@
}

function Post($uid,$type){
  $json = (@{ userId=$uid; type=$type } | ConvertTo-Json -Compress)
  $null = Curl-PostJson "$base/internal/study/events" $json
}

function Shift-AllToday($uid,$days){
  if($days -le 0){ return }

  Db @"
UPDATE study_events
SET created_at = DATE_SUB(created_at, INTERVAL $days DAY)
WHERE user_id=$uid AND DATE(created_at)=CURDATE();

UPDATE daily_learning
SET ymd = DATE_SUB(ymd, INTERVAL $days DAY)
WHERE user_id=$uid AND ymd=CURDATE();
"@
}

function Seed-Day($uid, $daysAgo, [scriptblock]$seedFn){
  & $seedFn
  Shift-AllToday $uid $daysAgo
}

function Get-Coach($uid){
  Curl-Text "$base/internal/study/coach?userId=$uid" | ConvertFrom-Json
}

function Save($uid,$tag,$obj){
  $dir = Join-Path $PSScriptRoot "artifacts"
  if(-not (Test-Path $dir)){ New-Item -ItemType Directory -Path $dir | Out-Null }

  $file = Join-Path $dir ("coach.day26.{0}.user{1}.{2}.json" -f $tag,$uid,(Get-Date -Format "HHmmssfff"))
  ($obj | ConvertTo-Json -Depth 8) | Out-File $file -Encoding utf8
}

function Get-PropValue($obj, [string]$name, $default = 0){
  if($null -eq $obj){ return $default }

  $p = $obj.PSObject.Properties[$name]
  if($null -eq $p){ return $default }
  if($null -eq $p.Value){ return $default }

  return $p.Value
}

function Print-Summary($uid,$tag,$c){
  $p = $c.prediction
  $e = if($p){ $p.evidence } else { $null }
  $s = $c.state

  $level      = Get-PropValue $p "level" "-"
  $reasonCode = Get-PropValue $p "reasonCode" "-"
  $nextAction = Get-PropValue $c "nextAction" "-"
  $daysSince  = Get-PropValue $e "daysSinceLastEvent" "-"
  $recent3d   = Get-PropValue $e "recentEventCount3d" "-"
  $streakDays = Get-PropValue $e "streakDays" "-"
  $eventsCnt  = Get-PropValue $s "eventsCount" 0
  $quizCnt    = Get-PropValue $s "quizSubmits" 0
  $wrongCnt   = Get-PropValue $s "wrongReviews" 0

  # wrong done 필드명 후보 둘 다 대응
  $wrongDone  = Get-PropValue $s "wrongReviewDone" $null
  if($null -eq $wrongDone){
    $wrongDone = Get-PropValue $s "wrongReviewsDone" 0
  }

  Write-Host ""
  Write-Host "[PHASE] $tag user=$uid" -ForegroundColor Cyan
  Write-Host (" level={0} reason={1} action={2}" -f $level,$reasonCode,$nextAction)
  Write-Host (" daysSince={0} recent3d={1} streak={2}" -f $daysSince,$recent3d,$streakDays)
  Write-Host (" events={0} quiz={1} wrong={2} wrongDone={3}" -f $eventsCnt,$quizCnt,$wrongCnt,$wrongDone)
}

function Run-Phase($uid,$tag,$seedFn){
  Reset-History $uid
  & $seedFn

  $coach = Get-Coach $uid
  Print-Summary $uid $tag $coach
  Save $uid $tag $coach
}

foreach($uid in $userIds){

  Write-Host ""
  Write-Host "=============================="
  Write-Host "DAY26 USER $uid"
  Write-Host "=============================="

  # baseline
  Run-Phase $uid "baseline" {
    # no events
  }

  # sparse : 3일 전 JUST_OPEN 1회
  Run-Phase $uid "sparse" {
    Seed-Day $uid 3 {
      Post $uid "JUST_OPEN"
    }
  }

  # steady : 2일 전 / 1일 전 / 오늘 꾸준한 학습
  Run-Phase $uid "steady" {
    Seed-Day $uid 2 {
      Post $uid "JUST_OPEN"
      Post $uid "QUIZ_SUBMIT"
    }

    Seed-Day $uid 1 {
      Post $uid "JUST_OPEN"
      Post $uid "QUIZ_SUBMIT"
    }

    Seed-Day $uid 0 {
      Post $uid "JUST_OPEN"
      Post $uid "QUIZ_SUBMIT"
    }
  }

  # open_only : 열기만 반복
  Run-Phase $uid "open_only" {
    Seed-Day $uid 0 {
      1..3 | ForEach-Object { Post $uid "JUST_OPEN" }
    }
  }

  # quiz_only : 퀴즈만 반복
  Run-Phase $uid "quiz_only" {
    Seed-Day $uid 0 {
      1..4 | ForEach-Object { Post $uid "QUIZ_SUBMIT" }
    }
  }

  # risk : 며칠에 걸친 오답 누적형
  Run-Phase $uid "risk" {
    Seed-Day $uid 2 {
      Post $uid "JUST_OPEN"
      Post $uid "QUIZ_SUBMIT"
      Post $uid "REVIEW_WRONG"
    }

    Seed-Day $uid 1 {
      Post $uid "JUST_OPEN"
      1..2 | ForEach-Object { Post $uid "REVIEW_WRONG" }
    }

    Seed-Day $uid 0 {
      Post $uid "JUST_OPEN"
    }
  }

  # recovery : 위험 후 복구형
  Run-Phase $uid "recovery" {
    Seed-Day $uid 2 {
      Post $uid "JUST_OPEN"
      Post $uid "QUIZ_SUBMIT"
      1..2 | ForEach-Object { Post $uid "REVIEW_WRONG" }
    }

    Seed-Day $uid 1 {
      Post $uid "JUST_OPEN"
      Post $uid "WRONG_REVIEW_DONE"
    }

    Seed-Day $uid 0 {
      Post $uid "JUST_OPEN"
      Post $uid "QUIZ_SUBMIT"
      1..2 | ForEach-Object { Post $uid "WRONG_REVIEW_DONE" }
    }
  }
}

Write-Host ""
Write-Host "DAY26 TUNED DONE" -ForegroundColor Green