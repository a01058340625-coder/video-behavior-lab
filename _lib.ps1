function New-Session() {
  New-Object Microsoft.PowerShell.Commands.WebRequestSession
}

function Read-JsonRaw($filePath) {
  Get-Content $filePath -Raw
}

function Post-JsonFile($url, $filePath, $session) {
  $body = Read-JsonRaw $filePath
  irm -Method Post $url -WebSession $session -ContentType "application/json" -Body $body
}

function Get-WithSession($url, $session) {
  irm $url -WebSession $session
}
