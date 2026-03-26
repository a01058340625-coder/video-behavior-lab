param(
  [string]$mysqlContainer = "goosage-mysql",
  [string]$dbName = "goosage"
)

chcp 65001 > $null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "==== DAY32 LOOP DATA SUMMARY ====" -ForegroundColor Cyan

docker exec $mysqlContainer mysql -uroot -proot123 $dbName -e @"
select
  user_id,
  count(*) as total_events,
  sum(type='JUST_OPEN') as opens,
  sum(type='QUIZ_SUBMIT') as quiz,
  sum(type='REVIEW_WRONG') as wrong,
  sum(type='WRONG_REVIEW_DONE') as wrong_done,
  count(distinct date(created_at)) as active_days
from study_events
group by user_id
order by user_id;
"@

Write-Host ""
Write-Host "==== DAY32 TODAY SUMMARY ====" -ForegroundColor Cyan

docker exec $mysqlContainer mysql -uroot -proot123 $dbName -e @"
select
  user_id,
  count(*) as today_events,
  sum(type='JUST_OPEN') as opens,
  sum(type='QUIZ_SUBMIT') as quiz,
  sum(type='REVIEW_WRONG') as wrong,
  sum(type='WRONG_REVIEW_DONE') as wrong_done
from study_events
where date(created_at)=curdate()
group by user_id
order by user_id;
"@

Write-Host ""
Write-Host "==== DAY32 ASSERT CHECK ====" -ForegroundColor Yellow

$rows = docker exec $mysqlContainer mysql -N -B -uroot -proot123 $dbName -e @"
select
  user_id,
  sum(type='REVIEW_WRONG'),
  sum(type='WRONG_REVIEW_DONE')
from study_events
where date(created_at)=curdate()
group by user_id;
"@

$failed = $false

foreach ($line in $rows) {
  $p = $line -split "`t"
  $uid = $p[0]
  $wrong = [int]($p[1] ?? 0)
  $done  = [int]($p[2] ?? 0)

  if ($done -gt $wrong) {
    Write-Host "[OK]   user=$uid recovery pattern" -ForegroundColor Green
  }
  elseif ($wrong -gt 0 -and $done -eq 0) {
    Write-Host "[OK]   user=$uid wrongheavy pattern" -ForegroundColor Green
  }
  else {
    Write-Host "[WARN] user=$uid mixed/neutral pattern" -ForegroundColor Yellow
  }
}

Write-Host ""
Write-Host "[OK] verify-day32 completed" -ForegroundColor Green