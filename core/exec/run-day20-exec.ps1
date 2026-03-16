param(
  [ValidateSet("seed","close","all")]
  [string]$mode = "all",

  [string]$base = "http://127.0.0.1:8083",
  [string]$internalKey = "goosage-dev",

  [long[]]$userIds = @(5, 9, 10, 12),

  # burnout 후보 userId=true/false 대신 간단히 리스트로 운용
  [long[]]$burnoutUsers = @(5, 12),

  [switch]$ResetHistory = $false,

  [string]$mysqlContainer = "goosage-mysql",
  [string]$dbName = "goosage",
  [string]$dbUser = "root",
  [string]$dbPass = "root123"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Utf8NoBom([string]$p,[string]$c){
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($p,$c,$enc)
}

function Curl-Text([string]$url,[hashtable]$headers=@{}){
  $h=@(); foreach($k in $headers.Keys){ $h += @("-H","${k}: $($headers[$k])") }
  & curl.exe -sS $h $url
}

function Curl-PostJson([string]$url,[string]$jsonBody,[hashtable]$headers=@{}){
  $tmp = Join-Path $env:TEMP ("req.day20.{0}.{1}.json" -f $PID,(Get-Random))
  Write-Utf8NoBom $tmp $jsonBody
  $h=@(); foreach($k in $headers.Keys){ $h += @("-H","${k}: $($headers[$k])") }
  $out = & curl.exe -sS -X POST $h -H "Content-Type: application/json" --data-binary "@$tmp" $url
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  return $out
}

function Db([string]$sql){
  & docker exec $mysqlContainer sh -lc "mysql -u$dbUser -p$dbPass $dbName -e `"$sql`""
}

function Reset-History([long]$uid){
  Db "DELETE FROM study_events WHERE user_id=$uid; DELETE FROM daily_learning WHERE user_id=$uid;" | Out-Host
}

function Post-Event([long]$uid,[string]$type){
  $json = ([ordered]@{ userId=$uid; type=$type } | ConvertTo-Json -Compress)
  $null = Curl-PostJson "$base/internal/study/events" $json @{ "X-INTERNAL-KEY" = $internalKey }
}

function Shift-Today([long]$uid,[int]$daysAgo){
  Db @"
UPDATE study_events
SET created_at = DATE_SUB(created_at, INTERVAL $daysAgo DAY)
WHERE user_id=$uid AND DATE(created_at)=CURDATE();

UPDATE daily_learning
SET ymd = DATE_SUB(ymd, INTERVAL $daysAgo DAY)
WHERE user_id=$uid AND ymd=CURDATE();
"@ | Out-Host
}

function Seed-HeavyDay([long]$uid,[int]$daysAgo){
  1..2 | % { Post-Event $uid "JUST_OPEN" }
  1..8 | % { Post-Event $uid "QUIZ_SUBMIT" }
  if($daysAgo -gt 0){ Shift-Today $uid $daysAgo }
}

function Seed-Burnout([long]$uid){
  if($ResetHistory){ Reset-History $uid }

  # 최근 3일은 과몰입
  Seed-HeavyDay $uid 1
  Seed-HeavyDay $uid 2
  Seed-HeavyDay $uid 3

  # 오늘은 0개 -> 공백
}

function Seed-Normal([long]$uid){
  if($ResetHistory){ Reset-History $uid }

  # 최근 3일도 적당히 유지, 오늘도 유지
  1..1 | % { Post-Event $uid "JUST_OPEN" }
  1..3 | % { Post-Event $uid "QUIZ_SUBMIT" }

  1..1 | % { Post-Event $uid "JUST_OPEN" }
  1..2 | % { Post-Event $uid "QUIZ_SUBMIT" }
  Shift-Today $uid 1

  1..1 | % { Post-Event $uid "JUST_OPEN" }
  1..2 | % { Post-Event $uid "QUIZ_SUBMIT" }
  Shift-Today $uid 2
}

function Get-Coach([long]$uid){
  Curl-Text "$base/internal/study/coach?userId=$uid" @{ "X-INTERNAL-KEY" = $internalKey }
}

function Save-Coach([long]$uid,[string]$tag,[string]$json){
  $ts=(Get-Date).ToString("yyyyMMdd-HHmmss")
  $dir=Join-Path $PSScriptRoot "artifacts"
  if(-not (Test-Path $dir)){ New-Item -ItemType Directory -Path $dir | Out-Null }
  $file=Join-Path $dir ("coach.day20.{0}.user{1}.{2}.json" -f $tag,$uid,$ts)
  Write-Utf8NoBom $file $json
}

if($mode -eq "seed" -or $mode -eq "all"){
  foreach($uid in $userIds){
    if($burnoutUsers -contains $uid){
      Seed-Burnout $uid
    } else {
      Seed-Normal $uid
    }
  }
}

if($mode -eq "close" -or $mode -eq "all"){
  foreach($uid in $userIds){
    $coach = Get-Coach $uid
    $coach | Out-Host
    Save-Coach $uid "close" $coach
  }
}

"DAY20 DONE"