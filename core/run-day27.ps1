param(
  [long[]]$userIds = @(5,9,10,12),

  [string]$base = "http://127.0.0.1:8083",
  [string]$internalKey = "goosage-dev",

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

function Write-Utf8NoBom([string]$path, [string]$content) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $content, $enc)
}

function Strip-Bom([string]$text) {
  if ([string]::IsNullOrEmpty($text)) { return $text }
  return $text.TrimStart([char]0xFEFF)
}

function Curl-Text([string]$url) {
  & curl.exe -sS -H "X-INTERNAL-KEY: $internalKey" $url
}

function Curl-PostJson([string]$url, [string]$json) {
  $tmp = Join-Path $env:TEMP ("req.day27.{0}.json" -f (Get-Random))
  $json = Strip-Bom $json
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

function Db([string]$sql) {
  if ([string]::IsNullOrWhiteSpace($sql)) { return }

  $sql = Strip-Bom $sql
  $sql = $sql -replace '^\uFEFF', ''

  & docker exec $mysqlContainer mysql `
    -N `
    "-u$dbUser" `
    "-p$dbPass" `
    $dbName `
    -e $sql
}

function Reset-History([long]$uid) {
  $sql = @(
    "DELETE FROM study_events WHERE user_id=$uid;",
    "DELETE FROM daily_learning WHERE user_id=$uid;"
  ) -join " "

  Db $sql | Out-Null
}

function Post([long]$uid, [string]$type) {
  $json = (@{ userId = $uid; type = $type } | ConvertTo-Json -Compress)
  $null = Curl-PostJson "$base/internal/study/events" $json
}

function Shift([long]$uid, [int]$days) {
  if ($days -le 0) { return }

  $sql = @(
    "START TRANSACTION;",
    "UPDATE study_events",
    "SET created_at = DATE_SUB(created_at, INTERVAL $days DAY)",
    "WHERE user_id=$uid",
    "AND DATE(created_at)=CURDATE();",

    "DELETE dl_today",
    "FROM daily_learning dl_today",
    "JOIN daily_learning dl_target",
    "ON dl_target.user_id = dl_today.user_id",
    "AND dl_target.ymd = DATE_SUB(dl_today.ymd, INTERVAL $days DAY)",
    "WHERE dl_today.user_id = $uid",
    "AND dl_today.ymd = CURDATE();",

    "UPDATE daily_learning",
    "SET ymd = DATE_SUB(ymd, INTERVAL $days DAY)",
    "WHERE user_id=$uid",
    "AND ymd=CURDATE();",

    "COMMIT;"
  ) -join " "

  Db $sql | Out-Null
}

function Seed-Day([long]$uid, [int]$daysAgo, [scriptblock]$seedFn) {
  & $seedFn
  Shift $uid $daysAgo
}

function Get-Coach([long]$uid) {
  Curl-Text "$base/internal/study/coach?userId=$uid" | ConvertFrom-Json
}

function Save([long]$uid, [string]$tag, [object]$obj) {
  $dir = Join-Path $PSScriptRoot "artifacts"
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir | Out-Null
  }

  $file = Join-Path $dir ("coach.day27.{0}.user{1}.{2}.json" -f $tag, $uid, (Get-Date -Format "yyyyMMdd-HHmmssfff"))
  ($obj | ConvertTo-Json -Depth 10) | Out-File $file -Encoding utf8
}

function Get-PropValue($obj, [string]$name, $default = $null) {
  if ($null -eq $obj) { return $default }
  $p = $obj.PSObject.Properties[$name]
  if ($null -eq $p) { return $default }
  if ($null -eq $p.Value) { return $default }
  return $p.Value
}

function Print-Summary([long]$uid, [string]$tag, [object]$c) {
  $p = $c.prediction
  $e = if ($p) { $p.evidence } else { $null }
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

  $wrongDone = Get-PropValue $s "wrongReviewDone" $null
  if ($null -eq $wrongDone) {
    $wrongDone = Get-PropValue $s "wrongReviewsDone" 0
  }

  Write-Host ""
  Write-Host "[PHASE] $tag user=$uid" -ForegroundColor Cyan
  Write-Host (" level={0} reason={1} action={2}" -f $level, $reasonCode, $nextAction)
  Write-Host (" daysSince={0} recent3d={1} streak={2}" -f $daysSince, $recent3d, $streakDays)
  Write-Host (" events={0} quiz={1} wrong={2} wrongDone={3}" -f $eventsCnt, $quizCnt, $wrongCnt, $wrongDone)
}

function Run-Phase([long]$uid, [string]$tag, [scriptblock]$seedFn) {
  Reset-History $uid
  & $seedFn

  $coach = Get-Coach $uid
  Print-Summary $uid $tag $coach
  Save $uid $tag $coach
}

foreach ($uid in $userIds) {

  Write-Host ""
  Write-Host "==============================" -ForegroundColor Yellow
  Write-Host "DAY27 USER $uid" -ForegroundColor Yellow
  Write-Host "==============================" -ForegroundColor Yellow

  Run-Phase $uid "baseline" {
  }

  Run-Phase $uid "comeback" {
    Seed-Day $uid 3 {
      Post $uid "JUST_OPEN"
    }

    Seed-Day $uid 0 {
      Post $uid "JUST_OPEN"
      Post $uid "QUIZ_SUBMIT"
    }
  }

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
      1..3 | ForEach-Object { Post $uid "QUIZ_SUBMIT" }
    }
  }

  Run-Phase $uid "risk" {
    Seed-Day $uid 2 {
      Post $uid "JUST_OPEN"
      1..2 | ForEach-Object { Post $uid "QUIZ_SUBMIT" }
      1..2 | ForEach-Object { Post $uid "REVIEW_WRONG" }
    }

    Seed-Day $uid 1 {
      Post $uid "JUST_OPEN"
      Post $uid "REVIEW_WRONG"
    }

    Seed-Day $uid 0 {
      Post $uid "JUST_OPEN"
      Post $uid "QUIZ_SUBMIT"
    }
  }

  Run-Phase $uid "recovery" {
    Seed-Day $uid 2 {
      Post $uid "JUST_OPEN"
      1..2 | ForEach-Object { Post $uid "QUIZ_SUBMIT" }
      1..2 | ForEach-Object { Post $uid "REVIEW_WRONG" }
    }

    Seed-Day $uid 1 {
      Post $uid "JUST_OPEN"
      Post $uid "WRONG_REVIEW_DONE"
      Post $uid "QUIZ_SUBMIT"
    }

    Seed-Day $uid 0 {
      Post $uid "JUST_OPEN"
      1..2 | ForEach-Object { Post $uid "QUIZ_SUBMIT" }
      1..3 | ForEach-Object { Post $uid "WRONG_REVIEW_DONE" }
    }
  }
}

Write-Host ""
Write-Host "DAY27 TUNED DONE" -ForegroundColor Green