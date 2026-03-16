# Video Behavior Lab

Video-based human behavior analysis pipeline.

## Goal

Extract behavior signals from video and convert them into:
- feature
- snapshot
- judgment
- next_action

---

## Current Pipeline

### Macro behavior pipeline
1. `walk.py`
2. `summarize_tracks.py`
3. `classify_behavior.py`
4. `session_snapshot.py`
5. `judge_session.py`

### Micro behavior pipeline
1. `pose_extract.py`
2. `hand_motion.py`
3. `leg_fidget.py`
4. `posture_sway.py`
5. `micro_behavior_snapshot.py`
6. `micro_behavior_judge.py`

---

## Current Micro Features

- `hand_motion_score`
- `leg_fidget_score`
- `posture_sway_score`

These are merged into:
- `micro_behavior_score`
- `micro_behavior_level`

Then converted into:
- `state`
- `reason_code`
- `message`
- `next_action`

---

## Current Judgment Example

- `STABLE`
- `RESTLESS`
- `HIGH_MICRO_MOTION`

Example next actions:
- `CONTINUE_MONITORING`
- `OBSERVE_LONGER`
- `CHECK_RESTLESS_PATTERN`

---

## Key Output Files

### Macro outputs
- `output/tracks.csv`
- `output/summary.csv`
- `output/behavior.csv`
- `output/session_snapshot.json`
- `output/session_judgment.json`

### Micro outputs
- `pose_output/pose_keypoints.csv`
- `pose_output/hand_motion_summary.csv`
- `pose_output/leg_fidget_summary.csv`
- `pose_output/posture_sway_summary.csv`
- `pose_output/micro_behavior_snapshot.json`
- `pose_output/micro_behavior_judgment.json`

---

## Run

### Micro pipeline
```powershell
.\run_micro_pipeline.ps1