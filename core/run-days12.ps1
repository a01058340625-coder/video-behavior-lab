param(
    [string]$base = "http://127.0.0.1:8083"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "run-days-common.ps1")

Write-Banner "run-days12 : PERSONA EXPANSION"

foreach ($user in $Global:GooUsers) {
    switch ($user.persona) {
        "steady"    { Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 0 -base $base -tag "days12" }
        "immersive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 5 -wrong 1 -base $base -tag "days12" }
        "burst"     { Invoke-UserScenario -user $user -justOpen 1 -quiz 3 -wrong 3 -base $base -tag "days12" }
        "gap"       { Invoke-UserScenario -user $user -justOpen 0 -quiz 0 -wrong 0 -base $base -tag "days12" }
        "recovery"  { Invoke-UserScenario -user $user -justOpen 1 -quiz 3 -wrong 1 -base $base -tag "days12" }
        "lowactive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 0 -wrong 0 -base $base -tag "days12" }
    }
}

Show-TodayDbSummary
Write-Banner "run-days12 DONE"