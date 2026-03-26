param(
    [string]$base = "http://127.0.0.1:8084"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "run-days-common.ps1")

Write-Banner "run-days18 : DAYS SINCE LAST EVENT ANALYSIS"

foreach ($user in $Global:GooUsers) {
    switch ($user.persona) {
        "steady"    { Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 0 -base $base -tag "days18" }
        "immersive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 4 -wrong 1 -base $base -tag "days18" }
        "burst"     { Invoke-UserScenario -user $user -justOpen 0 -quiz 0 -wrong 0 -base $base -tag "days18" }
        "gap"       { Invoke-UserScenario -user $user -justOpen 0 -quiz 0 -wrong 0 -base $base -tag "days18" }
        "recovery"  { Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 0 -base $base -tag "days18" }
        "lowactive" { Invoke-UserScenario -user $user -justOpen 0 -quiz 0 -wrong 0 -base $base -tag "days18" }
    }
}

Show-TodayDbSummary
Write-Banner "run-days18 DONE"