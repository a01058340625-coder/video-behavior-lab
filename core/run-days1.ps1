param(
    [string]$base = "http://127.0.0.1:8083"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "run-days-common.ps1")

Write-Banner "run-days1 : MULTI USER BASELINE"

# baseline
# steady      : 균형형
# immersive   : 퀴즈 강함
# burst       : 급발진 시작
# gap         : 최소 행동
# recovery    : 다시 붙는 단계
# lowactive   : 거의 안 하는 사용자

foreach ($user in $Global:GooUsers) {
    switch ($user.persona) {
        "steady"    { Invoke-UserScenario -user $user -justOpen 1 -quiz 3 -wrong 0 -base $base -tag "days1" }
        "immersive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 4 -wrong 0 -base $base -tag "days1" }
        "burst"     { Invoke-UserScenario -user $user -justOpen 1 -quiz 5 -wrong 1 -base $base -tag "days1" }
        "gap"       { Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 0 -base $base -tag "days1" }
        "recovery"  { Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 1 -base $base -tag "days1" }
        "lowactive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 0 -wrong 0 -base $base -tag "days1" }
    }
}

Show-TodayDbSummary
Write-Banner "run-days1 DONE"