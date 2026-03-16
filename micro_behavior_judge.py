# -*- coding: utf-8 -*-
import json

INPUT_JSON = r"C:\dev\walk\pose_output\micro_behavior_snapshot.json"
OUTPUT_JSON = r"C:\dev\walk\pose_output\micro_behavior_judgment.json"

with open(INPUT_JSON, "r", encoding="utf-8-sig") as f:
    snapshot = json.load(f)

tracks = snapshot.get("tracks", [])
results = []

for track in tracks:
    track_id = track["track_id"]
    hand_score = float(track["hand_motion_score"])
    leg_score = float(track["leg_fidget_score"])
    posture_score = float(track["posture_sway_score"])
    hand_rep_score = float(track.get("hand_repetition_score", 0.0))
    leg_rep_score = float(track.get("leg_repetition_score", 0.0))
    micro_score = float(track["micro_behavior_score"])

    state = "STABLE"
    reason_code = "LOW_MICRO_MOTION"
    message = "Micro motion is low and stable."
    next_action = "CONTINUE_MONITORING"

    if hand_rep_score >= 40 and leg_rep_score >= 40:
        state = "MULTI_REPETITIVE_SIGNAL"
        reason_code = "HIGH_HAND_AND_LEG_REPETITION"
        message = "Repeated hand and leg micro-motion detected."
        next_action = "CHECK_MULTI_REPETITION"

    elif hand_rep_score >= 40:
        state = "REPETITIVE_HAND_SIGNAL"
        reason_code = "HIGH_HAND_REPETITION"
        message = "Repeated hand micro-motion detected."
        next_action = "CHECK_HAND_PATTERN"

    elif leg_rep_score >= 40:
        state = "REPETITIVE_LEG_SIGNAL"
        reason_code = "HIGH_LEG_REPETITION"
        message = "Repeated leg micro-motion detected."
        next_action = "CHECK_LEG_PATTERN"

    elif micro_score >= 30:
        state = "HIGH_MICRO_MOTION"
        reason_code = "STRONG_RESTLESS_SIGNAL"
        message = "Strong micro-motion signal detected."
        next_action = "CHECK_RESTLESS_PATTERN"

    elif micro_score >= 12:
        state = "RESTLESS"
        reason_code = "MEDIUM_MICRO_MOTION"
        message = "Moderate restless micro-motion detected."
        next_action = "OBSERVE_LONGER"

    if posture_score >= 20 and state not in ("MULTI_REPETITIVE_SIGNAL",):
        reason_code = "HIGH_POSTURE_SWAY"
        message = "Posture sway is elevated."
        next_action = "CHECK_BODY_STABILITY"

    results.append({
        "track_id": track_id,
        "hand_motion_score": hand_score,
        "leg_fidget_score": leg_score,
        "posture_sway_score": posture_score,
        "hand_repetition_score": hand_rep_score,
        "leg_repetition_score": leg_rep_score,
        "micro_behavior_score": micro_score,
        "judgment": {
            "state": state,
            "reason_code": reason_code,
            "message": message
        },
        "next_action": next_action
    })

output = {
    "video": snapshot["video"],
    "track_count": snapshot["track_count"],
    "results": results
}

with open(OUTPUT_JSON, "w", encoding="utf-8-sig") as f:
    json.dump(output, f, ensure_ascii=False, indent=2)

print("DONE")
print(f"Micro judgment saved: {OUTPUT_JSON}")
print(json.dumps(output, ensure_ascii=False, indent=2))