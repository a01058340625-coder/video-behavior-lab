param(
  [string]$base = "http://127.0.0.1:8084"
)

$ErrorActionPreference = "Stop"

$script = Join-Path $PSScriptRoot "run-day37.ps1"

if (!(Test-Path $script)) {
  throw "run-day37.ps1 not found: $script"
}

& $script -mode seed -base $base