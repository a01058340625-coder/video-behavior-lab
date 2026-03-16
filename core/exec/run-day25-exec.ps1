param(
  [ValidateSet("seed","close","all")]
  [string]$mode = "all",

  [string]$base = "http://127.0.0.1:8083",
  [string]$internalKey = "goosage-dev",

  # userId=pattern
  [string]$patternMap = "5=steady,9=frontload,10=zigzag,12=steadyStrong",

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
  $h=@()
  foreach($k in $headers.Keys){ $h += @("-H","${k}: $($headers[$k])") }
  $out = & curl.exe -sS -X POST $h -H "Content-Type: application/json" --data-binary "@$tmp" $url
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  return $out
}

function Parse-Map([string]$text){
  $m=@{}
  foreach($pair in ($text -split ",")){
    $p=$pair.Trim()
    if(-not $p){ continue }
    $kv=$p -split "=",2
    if($kv.Count -ne 2){ continue }
    $m[[long]$kv[0].Trim()] = $kv[1].Trim()
  }
  return $m
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

function Seed-Day([long]$uid,[int]$offset,[int]$jo,[int]$quiz){
  if($jo -gt 0){ 1..$jo | % { Post-Event $uid "JUST_OPEN" } }
  if($quiz -gt 0){ 1..$quiz | % { Post-Event $uid "QUIZ_SUBMIT" } }
  if($offset -gt 0){ Shift-Today $uid $offset }
}

function Seed-Pattern([long]$uid,[string]$pattern){
  Warn "USER $uid pattern=$pattern"
  if($ResetHistory){ Reset-History $uid }

  switch($pattern.ToLower()){
    "steady" {
      Seed-Day $uid 0 1 2
      Seed-Day $uid 1 1 2
      Seed-Day $uid 2 1 2
      Seed-Day $uid 3 1 2
      Seed-Day $uid 4 1 2
    }
    "frontload" {
      Seed-Day $uid 4 2 6
      Seed-Day $uid 3 2 5
      Seed-Day $uid 2 1 2
      Seed-Day $uid 1 1 1
      Seed-Day $uid 0 1 0
    }
    "zigzag" {
      Seed-Day $uid 4 1 5
      Seed-Day $uid 3 0 1
      Seed-Day $uid 2 1 4
      Seed-Day $uid 1 0 1
      Seed-Day $uid 0 1 3
    }
    default {
      Seed-Day $uid 0 2 4
      Seed-Day $uid 1 2 4
      Seed-Day $uid 2 2 4
      Seed-Day $uid 3 2 4
      Seed-Day $uid 4 2 4
    }
  }
}

function Get-Coach([long]$uid){
  Curl-Text "$base/internal/study/coach?userId=$uid" @{ "X-INTERNAL-KEY" = $internalKey }
}

function Save-Coach([long]$uid,[string]$pattern,[string]$json){
  $ts=(Get-Date).ToString("yyyyMMdd-HHmmss")
  $dir=Join-Path $PSScriptRoot "artifacts"
  if(-not (Test-Path $dir)){ New-Item -ItemType Directory -Path $dir | Out-Null }
  $file=Join-Path $dir ("coach.day25.close.user{0}.{1}.{2}.json" -f $uid,$pattern,$ts)
  Write-Utf8NoBom $file $json
  Ok "saved => $file"
}

$map = Parse-Map $patternMap

if($mode -eq "seed" -or $mode -eq "all"){
  foreach($uid in ($map.Keys | Sort-Object)){
    Seed-Pattern $uid $map[$uid]
  }
}

if($mode -eq "close" -or $mode -eq "all"){
  foreach($uid in ($map.Keys | Sort-Object)){
    $coach = Get-Coach $uid
    $coach | Out-Host
    Save-Coach $uid $map[$uid] $coach
  }
}

Ok "DAY25 DONE"