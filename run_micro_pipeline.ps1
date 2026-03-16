Write-Host ""
Write-Host "===== VIDEO BEHAVIOR LAB : MICRO PIPELINE START ====="
Write-Host ""

Set-Location "C:\dev\walk"

Write-Host "[1/7] pose extraction"
python pose_extract.py
if ($LASTEXITCODE -ne 0) { throw "pose_extract.py failed" }

Write-Host ""
Write-Host "[2/7] hand motion"
python hand_motion.py
if ($LASTEXITCODE -ne 0) { throw "hand_motion.py failed" }

Write-Host ""
Write-Host "[3/7] leg fidget"
python leg_fidget.py
if ($LASTEXITCODE -ne 0) { throw "leg_fidget.py failed" }

Write-Host ""
Write-Host "[4/7] posture sway"
python posture_sway.py
if ($LASTEXITCODE -ne 0) { throw "posture_sway.py failed" }

Write-Host ""
Write-Host "[5/7] hand repetition"
python hand_repetition.py
if ($LASTEXITCODE -ne 0) { throw "hand_repetition.py failed" }

Write-Host ""
Write-Host "[6/7] micro snapshot"
python micro_behavior_snapshot.py
if ($LASTEXITCODE -ne 0) { throw "micro_behavior_snapshot.py failed" }

Write-Host ""
Write-Host "[7/7] micro judgment"
python micro_behavior_judge.py
if ($LASTEXITCODE -ne 0) { throw "micro_behavior_judge.py failed" }

Write-Host ""
Write-Host "===== MICRO PIPELINE DONE ====="
Write-Host ""

Write-Host "Result file:"
Write-Host "C:\dev\walk\pose_output\micro_behavior_judgment.json"
Write-Host ""