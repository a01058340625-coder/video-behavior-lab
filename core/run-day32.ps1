param(
  [int]$loops = 5,
  [string]$base = "http://127.0.0.1:8084",
  [string]$mysqlContainer = "goosage-mysql",
  [string]$dbName = "goosage"
)

chcp 65001 > $null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "run-days-common.ps1")

Write-Banner "DAY32 AUTO LOOP DATA GENERATION"

function Rand($min, $max) {
  return Get-Random -Minimum $min -Maximum ($max + 1)
}

foreach ($i in 1..$loops) {

  Write-Host ""
  Write-Host "===== LOOP $i =====" -ForegroundColor Cyan

  foreach ($user in $Global:GooUsers) {

    switch ($user.persona) {

      "steady" {
        Invoke-UserScenario -user $user `
          -justOpen (Rand 1 2) `
          -quiz (Rand 2 4) `
          -wrong 0 `
          -wrongDone 0 `
          -daysAgo (Rand 0 3) `
          -base $base -tag "day32"
      }

      "wrongheavy" {
        Invoke-UserScenario -user $user `
          -justOpen 1 `
          -quiz (Rand 1 2) `
          -wrong (Rand 3 6) `
          -wrongDone (Rand 0 1) `
          -daysAgo (Rand 0 2) `
          -base $base -tag "day32"
      }

      "recovery" {
        Invoke-UserScenario -user $user `
          -justOpen 1 `
          -quiz (Rand 1 2) `
          -wrong (Rand 0 2) `
          -wrongDone (Rand 2 5) `
          -daysAgo (Rand 0 2) `
          -base $base -tag "day32"
      }

      "comeback" {
        Invoke-UserScenario -user $user `
          -justOpen (Rand 1 2) `
          -quiz (Rand 0 1) `
          -wrong 0 `
          -wrongDone 0 `
          -daysAgo (Rand 0 4) `
          -base $base -tag "day32"
      }

      "anomaly" {
        Invoke-UserScenario -user $user `
          -justOpen (Rand 3 6) `
          -quiz 0 `
          -wrong 0 `
          -wrongDone 0 `
          -daysAgo 0 `
          -base $base -tag "day32"
      }

      "lowactive" {
        Invoke-UserScenario -user $user `
          -justOpen 1 `
          -quiz 0 `
          -wrong 0 `
          -wrongDone 0 `
          -daysAgo (Rand 0 5) `
          -base $base -tag "day32"
      }
    }
  }
}

Show-TodayDbSummary
Write-Banner "DAY32 DONE"