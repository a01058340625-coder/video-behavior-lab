param(
    [string]$base = "http://127.0.0.1:8083",
    [string]$internalKey = "goosage-dev",
    [long[]]$userIds = @(5),
    [int]$days = 5
)

$ErrorActionPreference = "Stop"

function Ok($m){ Write-Host "[OK]  $m" -ForegroundColor Green }
function Info($m){ Write-Host "[..]  $m" -ForegroundColor Cyan }

function Post-Event($uid, $type) {
    $body = @{
        userId = $uid
        type   = $type
    } | ConvertTo-Json -Compress

    $res = Invoke-RestMethod `
        -Method Post `
        -Uri "$base/internal/study/events" `
        -Headers @{ "X-INTERNAL-KEY" = $internalKey } `
        -ContentType "application/json" `
        -Body $body

    Write-Host "POST [$uid][$type] => $($res | ConvertTo-Json -Compress)"
}

function Get-MaxEventId($uid){
    $sql = "SELECT COALESCE(MAX(id), 0) AS max_id FROM study_events WHERE user_id = $uid;"
    $raw = docker exec goosage-mysql mysql -N -s -uroot -proot123 goosage -e $sql
    return [long]$raw.Trim()
}

function Shift-NewEventsOnly($uid, $daysAgo, $beforeId){
    $sql = @"
UPDATE study_events
SET created_at = DATE_SUB(created_at, INTERVAL $daysAgo DAY)
WHERE user_id = $uid
  AND id > $beforeId;
"@
    docker exec goosage-mysql mysql -uroot -proot123 goosage -e $sql | Out-Null
}

function Show-EventDates($uid){
    $sql = @"
SELECT id, user_id, type, created_at
FROM study_events
WHERE user_id = $uid
ORDER BY created_at DESC, id DESC
LIMIT 30;
"@
    docker exec goosage-mysql mysql -uroot -proot123 goosage -e $sql
}

function Get-Coach($uid){
    Invoke-RestMethod `
        -Method Get `
        -Uri "$base/internal/study/coach?userId=$uid" `
        -Headers @{ "X-INTERNAL-KEY" = $internalKey }
}

Write-Host ""
Write-Host "======================================="
Write-Host " GooSage INERTIA EXPERIMENT"
Write-Host "======================================="
Write-Host ""

foreach($uid in $userIds){

    Info "USER $uid inertia test"

    for($i=0; $i -lt $days; $i++){

        $shift = $days - $i - 1
        Info "Day $($i+1) -> shift $shift"

        $beforeId = Get-MaxEventId $uid

        Post-Event $uid "JUST_OPEN"
        Post-Event $uid "QUIZ_SUBMIT"
        Post-Event $uid "QUIZ_SUBMIT"
        Post-Event $uid "QUIZ_SUBMIT"

        if($shift -gt 0){
            Shift-NewEventsOnly $uid $shift $beforeId
        }
    }

    Write-Host ""
    Write-Host "---- EVENT CHECK ----"
    Show-EventDates $uid

    Write-Host ""
    Write-Host "---- COACH RESULT ----"
    $coach = Get-Coach $uid
    $coach | ConvertTo-Json -Depth 10
}

Write-Host ""
Ok "INERTIA TEST DONE"