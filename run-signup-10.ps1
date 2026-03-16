param(
  [string]$base = "http://127.0.0.1:8084",
  [string]$emailDomain = "goosage.test",
  [string]$password = "1234"
)

$ErrorActionPreference = "Stop"

function TrySignup([string]$url, [string]$bodyJson) {
  try {
    $out = & curl.exe -s -S -X POST $url -H "Content-Type: application/json" --data-binary $bodyJson
    if (-not $out) { return $null }
    return ($out | ConvertFrom-Json)
  } catch {
    return $null
  }
}

# ✅ signup endpoint 후보들(프로젝트마다 다를 수 있어서 순서대로 시도)
$signupUrls = @(
  "$base/auth/signup",
  "$base/auth/register",
  "$base/api/auth/signup",
  "$base/api/auth/register"
)

Write-Host "==== SIGNUP 10 USERS ====" -ForegroundColor Cyan

1..10 | ForEach-Object {
  $n = 100 + $_
  $email = "u$n@$emailDomain"
  $body = @{ email = $email; password = $password } | ConvertTo-Json -Compress

  $ok = $false
  foreach ($u in $signupUrls) {
    $resp = TrySignup $u $body
    if ($resp -ne $null -and ($resp.PSObject.Properties.Name -contains "success")) {
      if ($resp.success -eq $true) {
        Write-Host "OK signup: $email  via $u (id=$($resp.data.id))" -ForegroundColor Green
        $ok = $true
        break
      } else {
        # 이미 존재/중복일 수도 있음 -> 메시지 출력 후 다음 URL 시도는 중단
        Write-Host "FAIL signup: $email  via $u  message=$($resp.message)" -ForegroundColor Yellow
        $ok = $true
        break
      }
    }
  }

  if (-not $ok) {
    Write-Host "ERROR signup: $email  (no endpoint matched)" -ForegroundColor Red
    Write-Host "=> 너 프로젝트의 실제 회원가입 URL을 확인해야 함. (AuthController signup mapping)" -ForegroundColor Red
  }
}