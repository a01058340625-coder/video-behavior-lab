param(
    [string]$base = "http://127.0.0.1:8083"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "run-days-common.ps1")

Write-Banner "run-days10 : PREDICTION / NEXTACTION CONSISTENCY"

foreach ($user in $Global:GooUsers) {
    switch ($user.persona) {
        "steady"    { Invoke-UserScenario -user $user -justOpen 1 -quiz 3 -wrong 0 -base $base -tag "days10" }
        "immersive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 5 -wrong 1 -base $base -tag "days10" }
        "burst"     { Invoke-UserScenario -user $user -justOpen 1 -quiz 4 -wrong 3 -base $base -tag "days10" }
        "gap"       { Invoke-UserScenario -user $user -justOpen 0 -quiz 0 -wrong 0 -base $base -tag "days10" }
        "recovery"  { Invoke-UserScenario -user $user -justOpen 1 -quiz 3 -wrong 0 -base $base -tag "days10" }
        "lowactive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 0 -base $base -tag "days10" }
    }
}

Show-TodayDbSummary
Write-Banner "run-days10 DONE"