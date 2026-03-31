param(
    [string]$base = "http://127.0.0.1:8084"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "run-days-common.ps1")

Write-Banner "run-days20 : BURNOUT DETECTION EXPERIMENT"

foreach ($user in $Global:GooUsers) {
    switch ($user.persona) {
        "steady"    { Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 0 -base $base -tag "days20" }
        "immersive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 6 -wrong 4 -base $base -tag "days20" }
        "burst"     { Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 5 -base $base -tag "days20" }
        "gap"       { Invoke-UserScenario -user $user -justOpen 0 -quiz 0 -wrong 0 -base $base -tag "days20" }
        "recovery"  { Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 1 -base $base -tag "days20" }
        "lowactive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 0 -wrong 1 -base $base -tag "days20" }
    }
}

Show-TodayDbSummary
Write-Banner "run-days20 DONE"

