# run-days-common.ps1
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$root = $PSScriptRoot

. (Join-Path $root "persona-map.ps1")

function Write-Banner($text) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor DarkCyan
    Write-Host " $text" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor DarkCyan
}

function Invoke-ActionMany {
    param(
        [Parameter(Mandatory=$true)][int]$loginUserNo,
        [Parameter(Mandatory=$true)][int]$targetUserId,
        [Parameter(Mandatory=$true)][ValidateSet("JUST_OPEN","QUIZ_SUBMIT","REVIEW_WRONG","WRONG_REVIEW_DONE")][string]$action,
        [Parameter(Mandatory=$true)][int]$count,
        [string]$base = "http://127.0.0.1:8083"
    )

    if ($count -le 0) { return }

    for ($i = 1; $i -le $count; $i++) {
        $isLast = ($i -eq $count)

        if ($isLast) {
            & (Join-Path $root "run-event.ps1") `
                -loginUserNo $loginUserNo `
                -targetUserId $targetUserId `
                -action $action `
                -base $base
        }
        else {
            & (Join-Path $root "run-event.ps1") `
                -loginUserNo $loginUserNo `
                -targetUserId $targetUserId `
                -action $action `
                -base $base `
                -SkipCoach
        }
    }
}

function Invoke-UserScenario {
    param(
        [Parameter(Mandatory=$true)]$user,
        [Parameter(Mandatory=$true)][int]$justOpen,
        [Parameter(Mandatory=$true)][int]$quiz,
        [Parameter(Mandatory=$true)][int]$wrong,
        [int]$wrongDone = 0,
        [string]$base = "http://127.0.0.1:8083",
        [string]$tag = "days"
    )

    Write-Host ""
    Write-Host ("[{0}] login={1} target={2} persona={3} | open={4} quiz={5} wrong={6} wrongDone={7}" -f `
        $user.label, $user.loginUserNo, $user.targetUserId, $user.persona, $justOpen, $quiz, $wrong, $wrongDone) `
        -ForegroundColor Yellow

    Invoke-ActionMany -loginUserNo $user.loginUserNo -targetUserId $user.targetUserId -action "JUST_OPEN"         -count $justOpen  -base $base
    Invoke-ActionMany -loginUserNo $user.loginUserNo -targetUserId $user.targetUserId -action "QUIZ_SUBMIT"       -count $quiz      -base $base
    Invoke-ActionMany -loginUserNo $user.loginUserNo -targetUserId $user.targetUserId -action "REVIEW_WRONG"      -count $wrong     -base $base
    Invoke-ActionMany -loginUserNo $user.loginUserNo -targetUserId $user.targetUserId -action "WRONG_REVIEW_DONE" -count $wrongDone -base $base
}

function Show-TodayDbSummary {
    param(
        [string]$dbContainer = "goosage-mysql",
        [string]$dbName = "goosage"
    )

    Write-Banner "TODAY DB SUMMARY"

    docker exec $dbContainer mysql -uroot -proot123 $dbName -e @"
select user_id, type, count(*) cnt
from study_events
where date(created_at)=curdate()
group by user_id, type
order by user_id, type;
"@
}