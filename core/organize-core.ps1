param(
    [string]$Root = ".",
    [switch]$WhatIfMode = $false
)

$ErrorActionPreference = "Stop"

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Get-DateFolderFromName {
    param([string]$Name)

    # 파일명 안에 20260331-100510 같은 패턴 찾기
    if ($Name -match '(20\d{2})(\d{2})(\d{2})-\d{6}') {
        return "{0}-{1}-{2}" -f $matches[1], $matches[2], $matches[3]
    }

    return "unknown-date"
}

$rootPath = Resolve-Path $Root
Write-Host ""
Write-Host "========================================"
Write-Host " CORE FOLDER ORGANIZER START"
Write-Host " root = $rootPath"
Write-Host " whatIf = $WhatIfMode"
Write-Host "========================================"
Write-Host ""

# 기본 폴더 보장
$artifactsDir = Join-Path $rootPath "artifacts"
$coachDir     = Join-Path $artifactsDir "coach"
$verifyDir    = Join-Path $artifactsDir "verify"
$logsDir      = Join-Path $artifactsDir "logs"
$archiveDir   = Join-Path $artifactsDir "archive"
$tmpDir       = Join-Path $rootPath "tmp"
$cookiesDir   = Join-Path $rootPath "cookies"

Ensure-Dir $artifactsDir
Ensure-Dir $coachDir
Ensure-Dir $verifyDir
Ensure-Dir $logsDir
Ensure-Dir $archiveDir
Ensure-Dir $tmpDir
Ensure-Dir $cookiesDir

# 루트에 직접 쌓인 coach json만 대상으로 함
$files = Get-ChildItem -Path $rootPath -File | Where-Object {
    $_.Name -like "coach.after.login*.json"
}

if (-not $files -or $files.Count -eq 0) {
    Write-Host "No root-level coach.after.login*.json files found."
    Write-Host "Done."
    return
}

Write-Host ("Found {0} coach json files." -f $files.Count)
Write-Host ""

$moved = 0

foreach ($file in $files) {
    $dateFolder = Get-DateFolderFromName -Name $file.Name
    $targetDir  = Join-Path $coachDir $dateFolder
    Ensure-Dir $targetDir

    $targetPath = Join-Path $targetDir $file.Name

    if (Test-Path $targetPath) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $ext      = $file.Extension
        $stamp    = Get-Date -Format "yyyyMMdd-HHmmssfff"
        $targetPath = Join-Path $targetDir ("{0}.dup.{1}{2}" -f $baseName, $stamp, $ext)
    }

    if ($WhatIfMode) {
        Write-Host ("[WHATIF] MOVE {0} -> {1}" -f $file.FullName, $targetPath)
    }
    else {
        Move-Item -Path $file.FullName -Destination $targetPath
        Write-Host ("MOVED   {0} -> {1}" -f $file.Name, $targetDir)
    }

    $moved++
}

Write-Host ""
Write-Host "========================================"
Write-Host (" COMPLETE - moved {0} files" -f $moved)
Write-Host " coach dir   = $coachDir"
Write-Host " verify dir  = $verifyDir"
Write-Host " logs dir    = $logsDir"
Write-Host " archive dir = $archiveDir"
Write-Host "========================================"