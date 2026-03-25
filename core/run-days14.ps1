param(
    [string]$base = "http://127.0.0.1:8083"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "run-days-common.ps1")

Write-Banner "run-days14 : NEXTACTION ACCURACY VERIFY TUNED"

foreach ($user in $Global:GooUsers) {
    switch ($user.persona) {
        "steady" {
            Invoke-UserScenario -user $user -justOpen 1 -quiz 4 -wrong 0 -wrongDone 0 -base $base -tag "days14"
        }
        "immersive" {
            Invoke-UserScenario -user $user -justOpen 1 -quiz 6 -wrong 1 -wrongDone 0 -base $base -tag "days14"
        }
        "burst" {
            Invoke-UserScenario -user $user -justOpen 1 -quiz 2 -wrong 5 -wrongDone 0 -base $base -tag "days14"
        }
        "gap" {
            Invoke-UserScenario -user $user -justOpen 0 -quiz 0 -wrong 0 -wrongDone 0 -base $base -tag "days14"
        }
        "recovery" {
            Invoke-UserScenario -user $user -justOpen 1 -quiz 3 -wrong 1 -wrongDone 2 -base $base -tag "days14"
        }
        "lowactive" {
            Invoke-UserScenario -user $user -justOpen 1 -quiz 1 -wrong 0 -wrongDone 0 -base $base -tag "days14"
        }
    }
}

Show-TodayDbSummary
Write-Banner "run-days14 DONE"