# run-event-template.ps1
$ErrorActionPreference = "Stop"

$base   = "http://127.0.0.1:8084"
$cookie = ".\cookie.txt"

# 요청 바디를 파일로 만들어서(따옴표/이스케이프 문제 회피) 안정적으로 전송
$tmp = ".\tmp_event.json"
'{ "type": "TEMPLATE" }' | Out-File -Encoding ascii $tmp

Write-Host "==== EVENT: TEMPLATE ===="
curl.exe -i -b $cookie -X POST "$base/study/events" `
  -H "Content-Type: application/json" `
  --data-binary "@$tmp"