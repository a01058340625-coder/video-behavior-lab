param(
    [string]$base = "http://127.0.0.1:8083"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "run-days-common.ps1")

Write-Banner "run-days17 : RECENT3D IMPACT ANALYSIS"

foreach ($user in $Global:GooUsers) {
    switch ($user.persona) {
        "steady"    { Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 0 -base $base -tag "days17" }
        "immersive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 4 -wrong 1 -base $base -tag "days17" }
        "burst"     { Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 4 -base $base -tag "days17" }
        "gap"       { Invoke-UserScenario -user $user -justOpen 0 -quiz 0 -wrong 0 -base $base -tag "days17" }
        "recovery"  { Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 1 -base $base -tag "days17" }
        "lowactive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 0 -wrong 0 -base $base -tag "days17" }
    }
}

Show-TodayDbSummary
Write-Banner "run-days17 DONE"