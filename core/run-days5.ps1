param(
    [string]$base = "http://127.0.0.1:8083"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "run-days-common.ps1")

Write-Banner "run-days5 : RISK / WARNING REINFORCE"

foreach ($user in $Global:GooUsers) {
    switch ($user.persona) {
        "steady"    { Invoke-UserScenario -user $user -justOpen 1 -quiz 3 -wrong 1 -base $base -tag "days5" }
        "immersive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 5 -wrong 2 -base $base -tag "days5" }
        "burst"     { Invoke-UserScenario -user $user -justOpen 1 -quiz 4 -wrong 5 -base $base -tag "days5" }
        "gap"       { Invoke-UserScenario -user $user -justOpen 0 -quiz 0 -wrong 0 -base $base -tag "days5" }
        "recovery"  { Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 1 -base $base -tag "days5" }
        "lowactive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 0 -wrong 0 -base $base -tag "days5" }
    }
}

Show-TodayDbSummary
Write-Banner "run-days5 DONE"