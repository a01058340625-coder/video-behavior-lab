. "$PSScriptRoot\_lib.ps1"

$base = "http://127.0.0.1:8084"
$cj = New-Session

# 1) LOGIN (file-based)
Post-JsonFile "$base/auth/login" "$PSScriptRoot\samples\10-auth-login.ok.json" $cj | Out-Null
Write-Host "LOGIN OK"

# 2) COACH (session-based)
$coach = Get-WithSession "$base/study/coach" $cj
$coach | ConvertTo-Json -Depth 30