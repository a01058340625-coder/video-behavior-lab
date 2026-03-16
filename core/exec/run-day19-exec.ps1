param(
  [ValidateSet("sweep","close")]
  [string]$mode = "sweep",

  [string]$base = "http://127.0.0.1:8083",
  [string]$internalKey = "goosage-dev",

  [long[]]$userIds = @(5, 9, 10, 12),

  [switch]$ResetHistory = $false,

  # step1 고활동 -> step4 저활동
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

function Write-Utf8NoBom([string]$p,[string]$c){
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($p,$c,$enc)
}

function Curl-Text([string]$url,[hashtable]$headers=@{}){
  $h=@(); foreach($k in $headers.Keys){ $h += @("-H","${k}: $($headers[$k])") }
  & curl.exe -sS $h $url
}

function Curl-PostJson([string]$url,[string]$jsonBody,[hashtable]$headers=@{}){
  $tmp = Join-Path $env:TEMP ("req.day19.{0}.{1}.json" -f $PID,(Get-Random))
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

function Step-Config([int]$step){
  switch($step){
    1 { @{ jo=$step1_jo; quiz=$step1_quiz } }
    2 { @{ jo=$step2_jo; quiz=$step2_quiz } }
    3 { @{ jo=$step3_jo; quiz=$step3_quiz } }
    default { @{ jo=$step4_jo; quiz=$step4_quiz } }
  }
}

function Get-Coach([long]$uid){
  Curl-Text "$base/internal/study/coach?userId=$uid" @{ "X-INTERNAL-KEY" = $internalKey }
}

function Save-Coach([long]$uid,[string]$tag,[string]$json){
  $ts=(Get-Date).ToString("yyyyMMdd-HHmmss")
  $dir=Join-Path $PSScriptRoot "artifacts"
  if(-not (Test-Path $dir)){ New-Item -ItemType Directory -Path $dir | Out-Null }
  $file=Join-Path $dir ("coach.day19.{0}.user{1}.{2}.json" -f $tag,$uid,$ts)
  Write-Utf8NoBom $file $json
}

if($mode -eq "close"){
  foreach($uid in $userIds){
    $coach = Get-Coach $uid
    $coach | Out-Host
    Save-Coach $uid "close" $coach
  }
  exit 0
}

foreach($uid in $userIds){
  if($ResetHistory){ Reset-History $uid }

  for($s=1;$s -le 4;$s++){
    $c = Step-Config $s
    if($c.jo -gt 0){ 1..$c.jo | % { Post-Event $uid "JUST_OPEN" } }
    if($c.quiz -gt 0){ 1..$c.quiz | % { Post-Event $uid "QUIZ_SUBMIT" } }

    $coach = Get-Coach $uid
    $coach | Out-Host
    Save-Coach $uid ("s{0}" -f $s) $coach
  }
}

"DAY19 DONE"