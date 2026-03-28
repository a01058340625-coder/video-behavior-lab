param(
  [Parameter(Mandatory=$true)][int]$userId,
  [string]$base = "http://127.0.0.1:8083",
  [string]$cookie
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

# ✅ cookie 기본값 (user별)
if ([string]::IsNullOrWhiteSpace($cookie)) {
  $cookiesDir = Join-Path $root "cookies"
  if (!(Test-Path $cookiesDir)) {
    New-Item -ItemType Directory -Path $cookiesDir | Out-Null
  }
  $cookie = Join-Path $cookiesDir ("cookie.u{0}.txt" -f $userId)
}

# ✅ user별 로그인 JSON 자동 선택
$loginBody = Join-Path $root ("samples\http-auth-login.u{0}.req.json" -f $userId)

if (!(Test-Path $loginBody)) {
  throw "로그인 JSON 없음: $loginBody"
}

Write-Host "==== LOGIN user=$userId (cookie saved) ===="

curl.exe -i -c $cookie -X POST "$base/auth/login" `
  -H "Content-Type: application/json" `
  --data-binary "@$loginBody"

Write-Host ""
Write-Host "Cookie file => $cookie"