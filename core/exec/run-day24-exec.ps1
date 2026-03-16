param(
  [ValidateSet("seed","close","all")]
  [string]$mode = "all",

  [string]$base = "http://127.0.0.1:8083",
  [string]$internalKey = "goosage-dev",

  [long[]]$userIds = @(5, 9, 10, 12),

  # 위험형 패턴 강도
  # weak / medium / hard / collapse
  [string]$riskMap = "5=weak,9=medium,10=hard,12=collapse",

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
  $tmp = Join-Path $env:TEMP ("req.day24.{0}.{1}.json" -f $PID,(Get-Random))
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

function Seed-Day([long]$uid,[int]$dayOffset,[int]$jo,[int]$quiz){
  if($jo -gt 0){ 1..$jo | % { Post-Event $uid "JUST_OPEN" } }
  if($quiz -gt 0){ 1..$quiz | % { Post-Event $uid "QUIZ_SUBMIT" } }
  if($dayOffset -gt 0){ Shift-Today $uid $dayOffset }
}

function Seed-RiskTrack([long]$uid,[string]$kind){
  Warn "USER $uid risk=$kind"
  if($ResetHistory){ Reset-History $uid }

  switch($kind.ToLower()){
    "weak" {
      Seed-Day $uid 0 1 1
      Seed-Day $uid 2 1 1
      Seed-Day $uid 4 1 0
    }
    "medium" {
      Seed-Day $uid 0 1 0
      Seed-Day $uid 3 1 1
      Seed-Day $uid 6 1 0
    }
    "hard" {
      Seed-Day $uid 0 0 1
      Seed-Day $uid 5 1 0
      Seed-Day $uid 10 1 1
    }
    default {
      Seed-Day $uid 7 1 1
      Seed-Day $uid 14 1 0
      Seed-Day $uid 21 1 0
    }
  }
}

function Get-Coach([long]$uid){
  Curl-Text "$base/internal/study/coach?userId=$uid" @{ "X-INTERNAL-KEY" = $internalKey }
}

function Save-Coach([long]$uid,[string]$kind,[string]$json){
  $ts=(Get-Date).ToString("yyyyMMdd-HHmmss")
  $dir=Join-Path $PSScriptRoot "artifacts"
  if(-not (Test-Path $dir)){ New-Item -ItemType Directory -Path $dir | Out-Null }
  $file=Join-Path $dir ("coach.day24.close.user{0}.{1}.{2}.json" -f $uid,$kind,$ts)
  Write-Utf8NoBom $file $json
  Ok "saved => $file"
}

$map = Parse-Map $riskMap

if($mode -eq "seed" -or $mode -eq "all"){
  foreach($uid in ($map.Keys | Sort-Object)){
    Seed-RiskTrack $uid $map[$uid]
  }
}

if($mode -eq "close" -or $mode -eq "all"){
  foreach($uid in ($map.Keys | Sort-Object)){
    $coach = Get-Coach $uid
    $coach | Out-Host
    Save-Coach $uid $map[$uid] $coach
  }
}

Ok "DAY24 DONE"