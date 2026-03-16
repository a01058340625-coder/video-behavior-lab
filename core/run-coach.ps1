param(
  [int]$userId = 12,
  [string]$base = "http://127.0.0.1:8083",
  [string]$samplesDir = ".\samples",
  [string]$loginFile = "http-auth-login.req.json"
)

$ErrorActionPreference = "Stop"
$cj = New-Object Microsoft.PowerShell.Commands.WebRequestSession

function ReadJson([string]$dir, [string]$file) {
  $p = Join-Path $dir $file
  if (-not (Test-Path $p)) { throw "Missing file: $p" }
  return Get-Content $p -Raw -Encoding utf8
}

Write-Host "==== 0) HEALTH ====" -ForegroundColor DarkCyan
irm -Method Get -Uri "$base/health" | Out-Null
Write-Host "OK"

Write-Host "==== 1) LOGIN ====" -ForegroundColor Cyan

# ??PATCH: userId 湲곕컲 loginFile ?먮룞 ?좏깮
# 湲곕낯媛?http-auth-login.req.json)???곌퀬 ?덉쓣 ?뚮쭔, u{userId} ?꾩슜 ?뚯씪???덉쑝硫?洹멸구濡?諛붽씔??
if ($loginFile -eq "http-auth-login.req.json") {
  $candidate = "http-auth-login.u$userId.req.json"
  $p = Join-Path $samplesDir $candidate
  if (Test-Path $p) {
    $loginFile = $candidate
  }
}
Write-Host ("loginFile=" + $loginFile) -ForegroundColor DarkGray

$loginBody = ReadJson $samplesDir $loginFile
$login = irm -Method Post -Uri "$base/auth/login" -ContentType "application/json" -Body $loginBody -WebSession $cj
if ($login.success -ne $true) { throw "login failed" }
Write-Host ("login userId=" + $login.data.id)

Write-Host "==== 1.1) COOKIE CHECK ====" -ForegroundColor DarkCyan
$cookieHeader = $cj.Cookies.GetCookieHeader($base)
Write-Host $cookieHeader
if ($cookieHeader -notmatch "JSESSIONID") { throw "JSESSIONID missing" }

Write-Host "==== 2) COACH ====" -ForegroundColor Cyan
$c = irm -Method Get -Uri "$base/study/coach?userId=$userId" -WebSession $cj
$c | ConvertTo-Json -Depth 20

