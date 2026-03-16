param(
    [string]$base = "http://127.0.0.1:8083"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "run-days-common.ps1")

Write-Banner "run-days9 : WRONG REVIEW VERIFY"

foreach ($user in $Global:GooUsers) {
    switch ($user.persona) {
        "steady"    { Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 1 -base $base -tag "days9" }
        "immersive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 4 -wrong 2 -base $base -tag "days9" }
        "burst"     { Invoke-UserScenario -user $user -justOpen 1 -quiz 3 -wrong 4 -base $base -tag "days9" }
        "gap"       { Invoke-UserScenario -user $user -justOpen 0 -quiz 0 -wrong 1 -base $base -tag "days9" }
        "recovery"  { Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 2 -base $base -tag "days9" }
        "lowactive" { Invoke-UserScenario -user $user -justOpen 1 -quiz 0 -wrong 1 -base $base -tag "days9" }
    }
}

Show-TodayDbSummary
Write-Banner "run-days9 DONE"