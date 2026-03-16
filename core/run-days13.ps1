param(
    [string]$base = "http://127.0.0.1:8083"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "run-days-common.ps1")

Write-Banner "run-days13 : EVENT RATIO VARIATION"

foreach ($user in $Global:GooUsers) {
    switch ($user.persona) {
        "steady"    { Invoke-UserScenario -user $user -justOpen 1 -quiz 4 -wrong 0 -base $base -tag "days13" }
        "immersive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 7 -wrong 1 -base $base -tag "days13" }
        "burst"     { Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 5 -base $base -tag "days13" }
        "gap"       { Invoke-UserScenario -user $user -justOpen 0 -quiz 0 -wrong 0 -base $base -tag "days13" }
        "recovery"  { Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 1 -base $base -tag "days13" }
        "lowactive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 0 -base $base -tag "days13" }
    }
}

Show-TodayDbSummary
Write-Banner "run-days13 DONE"