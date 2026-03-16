$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

function Run-One($uid, $act){
  Write-Host ""
  Write-Host ("===== Day1 persona userId={0} action={1} =====" -f $uid, $act) -ForegroundColor Magenta
  & (Join-Path $root "run-event.ps1") -userId $uid -action $act | Out-Host
}

# ============================================
# GooSage Persona Day1
# 하루 1회만 실행 (중요)
# ============================================

# 12 = 모범형
Run-One 12 "QUIZ_SUBMIT"

# 13 = 게으른형
Run-One 13 "JUST_OPEN"

# 14 = 오답형
Run-One 14 "REVIEW_WRONG"

# 15 = 초보형
Run-One 15 "QUIZ_SUBMIT"

# 16 = 꾸준형
Run-One 16 "QUIZ_SUBMIT"

# 17 = 번아웃형(초반 몰입)
Run-One 17 "QUIZ_SUBMIT"

# 18 = 불규칙형
Run-One 18 "JUST_OPEN"

# 19 = 과몰입형 (오늘은 1회만!)
Run-One 19 "QUIZ_SUBMIT"

# 20 = 주말몰빵형 => Day1 공백(의도적으로 실행 안 함)

# 21 = 포기 직전형
Run-One 21 "JUST_OPEN"

Write-Host ""
Write-Host "DONE: Day1 persona executed (except userId=20 intentionally blank)" -ForegroundColor Green