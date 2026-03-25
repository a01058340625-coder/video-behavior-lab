param(
    [string]$base = "http://127.0.0.1:8084"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "run-days-common.ps1")

Write-Banner "run-days15 : RISK SENSITIVITY CHECK TUNED"

foreach ($user in $Global:GooUsers) {
    switch ($user.persona) {
        "steady" {
            Invoke-UserScenario -user $user -justOpen 1 -quiz 3 -wrong 0 -wrongDone 0 -base $base -tag "days15"
        }
        "immersive" {
            Invoke-UserScenario -user $user -justOpen 1 -quiz 5 -wrong 2 -wrongDone 0 -base $base -tag "days15"
        }
        "burst" {
            Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 6 -wrongDone 0 -base $base -tag "days15"
        }
        "gap" {
            Invoke-UserScenario -user $user -justOpen 0 -quiz 0 -wrong 0 -wrongDone 0 -base $base -tag "days15"
        }
        "recovery" {
            Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 2 -wrongDone 2 -base $base -tag "days15"
        }
        "lowactive" {
            Invoke-UserScenario -user $user -justOpen 1 -quiz 0 -wrong 1 -wrongDone 0 -base $base -tag "days15"
        }
    }
}

Show-TodayDbSummary
Write-Banner "run-days15 DONE"