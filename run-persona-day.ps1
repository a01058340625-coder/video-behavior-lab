param(
  [Parameter(Mandatory=$true)][int]$day,
  [string]$personaFile = ".\persona\persona-10.json",
  [string]$logFile = ".\logs\persona-log.csv"
)

$ErrorActionPreference = "Stop"

function Assert-True([bool]$cond, [string]$msg) { if (-not $cond) { throw "ASSERT FAIL: $msg" } }

if (!(Test-Path $personaFile)) { throw "Missing persona file: $personaFile" }
if (!(Test-Path ".\logs")) { New-Item -ItemType Directory ".\logs" | Out-Null }

# 헤더
if (!(Test-Path $logFile)) {
  "day,user,persona,eventsCount,streakDays,recentEventCount3d,reasonCode,nextActionType" | Out-File $logFile -Encoding utf8
}

$data = Get-Content $personaFile -Raw | ConvertFrom-Json

foreach ($p in $data) {
  $user    = [string]$p.user
  $persona = [string]$p.persona
  $action  = [string]$p.d[$day-1]

  if ($action -eq $null -or $action -eq "" -or $action -eq "none") { continue }

  # eventN 처리 (event, event3, event5 등)
  $count = 1
  if ($action -match "^event(\d+)$") { $count = [int]$Matches[1]; $action = "event" }

  # 오늘은 event만 실행(실습 붙이기)
  if ($action -ne "event") { continue }

  $loginFile = "http-auth-login.$user.req.json"

  for ($i=0; $i -lt $count; $i++) {
    .\run-login-event-coach.ps1 -loginFile $loginFile | Out-Null
  }

  # 방금 실행 결과는 coach.after.json 에 저장됨(너 스크립트가 그렇게 만듦)
  $coachPath = ".\coach.after.json"
  Assert-True (Test-Path $coachPath) "Missing coach output: $coachPath"

  $c = Get-Content $coachPath -Raw -Encoding utf8 | ConvertFrom-Json

  $eventsCount = [int]$c.data.state.eventsCount
  $streakDays  = [int]$c.data.prediction.evidence.streakDays
  $recent3d    = [int]$c.data.prediction.evidence.recentEventCount3d
  $reasonCode  = [string]$c.data.prediction.reasonCode
  $nextType    = [string]$c.data.nextAction.type

  "$day,$user,$persona,$eventsCount,$streakDays,$recent3d,$reasonCode,$nextType" |
    Add-Content $logFile -Encoding utf8
}

"OK. wrote $logFile"