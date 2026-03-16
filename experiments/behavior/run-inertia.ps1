param(
    [string]$base = "http://127.0.0.1:8083",
    [string]$internalKey = "goosage-dev",

    # inertia 실험 대상 사용자
    [long[]]$userIds = @(5),

    # 몇 일 streak 만들지
    [int]$days = 5
)

$ErrorActionPreference = "Stop"

function Ok($m){ Write-Host "[OK]  $m" -ForegroundColor Green }
function Info($m){ Write-Host "[..]  $m" -ForegroundColor Cyan }

function Post-Event($uid, $type) {

    $json = @{
        userId = $uid
        type   = $type
    } | ConvertTo-Json -Compress

    curl.exe -s -X POST "$base/internal/study/events" `
        -H "X-INTERNAL-KEY: $internalKey" `
        -H "Content-Type: application/json" `
        --data-binary $json | Out-Null
}

function Shift-Day($uid, $daysAgo){

$sql = @"
UPDATE study_events
SET created_at = DATE_SUB(created_at, INTERVAL $daysAgo DAY)
WHERE user_id=$uid AND DATE(created_at)=CURDATE();

UPDATE daily_learning
SET ymd = DATE_SUB(ymd, INTERVAL $daysAgo DAY)
WHERE user_id=$uid AND ymd=CURDATE();
"@

docker exec goosage-mysql sh -lc "mysql -uroot -proot123 goosage -e `"$sql`"" | Out-Null
}

function Get-Coach($uid){

    $url = "$base/internal/study/coach?userId=$uid"

    curl.exe -s `
        -H "X-INTERNAL-KEY: $internalKey" `
        $url
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

        Post-Event $uid "JUST_OPEN"
        Post-Event $uid "QUIZ_SUBMIT"
        Post-Event $uid "QUIZ_SUBMIT"
        Post-Event $uid "QUIZ_SUBMIT"

        if($shift -gt 0){
            Shift-Day $uid $shift
        }
    }

    Write-Host ""
    Write-Host "---- COACH RESULT ----"

    $coach = Get-Coach $uid

    $coach

}

Write-Host ""
Ok "INERTIA TEST DONE"