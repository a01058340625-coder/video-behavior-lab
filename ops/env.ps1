# GooSage ENV FIX (Docker 환경 기준)

# API base
$env:GOOSAGE_BASE="http://127.0.0.1:8083"

# Spring profile
$env:SPRING_PROFILES_ACTIVE="local"

# Internal key
$env:GOOSAGE_INTERNAL_KEY="goosage-dev"

# Docker mysql info
$env:GOOSAGE_DB_NAME="goosage"
$env:GOOSAGE_DB_USER="root"
$env:GOOSAGE_DB_PASSWORD="root123"

Write-Host ""
Write-Host "GooSage ENV Loaded"
Write-Host "BASE      :" $env:GOOSAGE_BASE
Write-Host "PROFILE   :" $env:SPRING_PROFILES_ACTIVE
Write-Host "DB NAME   :" $env:GOOSAGE_DB_NAME
Write-Host ""