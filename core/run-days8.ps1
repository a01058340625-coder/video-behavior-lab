param(
    [string]$base = "http://127.0.0.1:8083"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "run-days-common.ps1")

Write-Banner "run-days8 : RETURN REINFORCE"

foreach ($user in $Global:GooUsers) {
    switch ($user.persona) {
        "steady"    { Invoke-UserScenario -user $user -justOpen 1 -quiz 3 -wrong 0 -base $base -tag "days8" }
        "immersive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 5 -wrong 1 -base $base -tag "days8" }
        "burst"     { Invoke-UserScenario -user $user -justOpen 1 -quiz 3 -wrong 1 -base $base -tag "days8" }
        "gap"       { Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 0 -base $base -tag "days8" }
        "recovery"  { Invoke-UserScenario -user $user -justOpen 1 -quiz 4 -wrong 0 -base $base -tag "days8" }
        "lowactive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 0 -base $base -tag "days8" }
    }
}

Show-TodayDbSummary
Write-Banner "run-days8 DONE"