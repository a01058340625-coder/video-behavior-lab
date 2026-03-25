param(
    [string]$base = "http://127.0.0.1:8083"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "run-days-common.ps1")

Write-Banner "run-days16 : STREAK EFFECT VERIFY TUNED"

foreach ($user in $Global:GooUsers) {
    switch ($user.persona) {
        "steady" {
            Invoke-UserScenario -user $user -justOpen 1 -quiz 3 -wrong 0 -wrongDone 0 -daysAgo 2 -base $base -tag "days16"
            Invoke-UserScenario -user $user -justOpen 1 -quiz 3 -wrong 0 -wrongDone 0 -daysAgo 1 -base $base -tag "days16"
            Invoke-UserScenario -user $user -justOpen 1 -quiz 3 -wrong 0 -wrongDone 0 -daysAgo 0 -base $base -tag "days16"
        }
        "immersive" {
            Invoke-UserScenario -user $user -justOpen 1 -quiz 5 -wrong 1 -wrongDone 0 -daysAgo 2 -base $base -tag "days16"
            Invoke-UserScenario -user $user -justOpen 1 -quiz 5 -wrong 1 -wrongDone 0 -daysAgo 1 -base $base -tag "days16"
            Invoke-UserScenario -user $user -justOpen 1 -quiz 5 -wrong 1 -wrongDone 0 -daysAgo 0 -base $base -tag "days16"
        }
        "burst" {
            Invoke-UserScenario -user $user -justOpen 1 -quiz 3 -wrong 3 -wrongDone 0 -daysAgo 0 -base $base -tag "days16"
        }
        "gap" {
            Invoke-UserScenario -user $user -justOpen 0 -quiz 0 -wrong 0 -wrongDone 0 -daysAgo 0 -base $base -tag "days16"
        }
        "recovery" {
            Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 1 -wrongDone 1 -daysAgo 1 -base $base -tag "days16"
            Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 0 -wrongDone 2 -daysAgo 0 -base $base -tag "days16"
        }
        "lowactive" {
            Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 0 -wrongDone 0 -daysAgo 0 -base $base -tag "days16"
        }
    }
}

Show-TodayDbSummary
Write-Banner "run-days16 DONE"