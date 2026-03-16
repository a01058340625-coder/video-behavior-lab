param(
  [ValidateSet("seed","close","all")]
  [string]$mode = "all",

  [string]$base = "http://127.0.0.1:8083",
  [string]$internalKey = "goosage-dev",

  # userId=plan
  [string]$planMap = "5=open1,9=open1quiz1,10=quiz1,12=open2quiz1",

  # 며칠 유지할지
  [int]$days = 5,

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
  $tmp = Join-Path $env:TEMP ("req.day23.{0}.{1}.json" -f $PID,(Get-Random))
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

function Apply-Plan([long]$uid,[string]$plan){
  switch($plan.ToLower()){
    "open1" {
      Post-Event $uid "JUST_OPEN"
    }
    "open1quiz1" {
      Post-Event $uid "JUST_OPEN"
      Post-Event $uid "QUIZ_SUBMIT"
    }
    "quiz1" {
      Post-Event $uid "QUIZ_SUBMIT"
    }
    default {
      1..2 | % { Post-Event $uid "JUST_OPEN" }
      1..1 | % { Post-Event $uid "QUIZ_SUBMIT" }
    }
  }
}

function Get-Coach([long]$uid){
  Curl-Text "$base/internal/study/coach?userId=$uid" @{ "X-INTERNAL-KEY" = $internalKey }
}

function Save-Coach([long]$uid,[string]$tag,[string]$plan,[string]$json){
  $ts=(Get-Date).ToString("yyyyMMdd-HHmmss")
  $dir=Join-Path $PSScriptRoot "artifacts"
  if(-not (Test-Path $dir)){ New-Item -ItemType Directory -Path $dir | Out-Null }
  $file=Join-Path $dir ("coach.day23.{0}.user{1}.{2}.{3}.json" -f $tag,$uid,$plan,$ts)
  Write-Utf8NoBom $file $json
  Ok "saved => $file"
}

$map = Parse-Map $planMap

if($mode -eq "seed" -or $mode -eq "all"){
  foreach($uid in ($map.Keys | Sort-Object)){
    $plan = $map[$uid]
    Warn "USER $uid plan=$plan days=$days"

    if($ResetHistory){ Reset-History $uid }

    for($d=0; $d -lt $days; $d++){
      Apply-Plan $uid $plan
      if($d -gt 0){ Shift-Today $uid $d }
    }

    $coach = Get-Coach $uid
    $coach | Out-Host
    Save-Coach $uid "close" $plan $coach
  }
}

if($mode -eq "close"){
  foreach($uid in ($map.Keys | Sort-Object)){
    $plan = $map[$uid]
    $coach = Get-Coach $uid
    $coach | Out-Host
    Save-Coach $uid "close" $plan $coach
  }
}

Ok "DAY23 DONE"