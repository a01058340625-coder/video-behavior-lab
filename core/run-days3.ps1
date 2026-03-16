param(
    [string]$base = "http://127.0.0.1:8083"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "run-days-common.ps1")

Write-Banner "run-days3 : PATTERN DIVERGENCE"

foreach ($user in $Global:GooUsers) {
    switch ($user.persona) {
        "steady"    { Invoke-UserScenario -user $user -justOpen 1 -quiz 4 -wrong 1 -base $base -tag "days3" }
        "immersive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 7 -wrong 1 -base $base -tag "days3" }
        "burst"     { Invoke-UserScenario -user $user -justOpen 1 -quiz 8 -wrong 4 -base $base -tag "days3" }
        "gap"       { Invoke-UserScenario -user $user -justOpen 0 -quiz 0 -wrong 0 -base $base -tag "days3" }
        "recovery"  { Invoke-UserScenario -user $user -justOpen 1 -quiz 3 -wrong 1 -base $base -tag "days3" }
        "lowactive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 0 -base $base -tag "days3" }
    }
}

Show-TodayDbSummary
Write-Banner "run-days3 DONE"