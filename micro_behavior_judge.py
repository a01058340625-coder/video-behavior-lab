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
    micro_score = float(track["micro_behavior_score"])

    state = "STABLE"
    reason_code = "LOW_MICRO_MOTION"
    message = "Micro motion is low and stable."
    next_action = "CONTINUE_MONITORING"

    if micro_score >= 25:
        state = "HIGH_MICRO_MOTION"
        reason_code = "STRONG_RESTLESS_SIGNAL"
        message = "Strong micro-motion signal detected."
        next_action = "CHECK_RESTLESS_PATTERN"

    elif micro_score >= 10:
        state = "RESTLESS"
        reason_code = "MEDIUM_MICRO_MOTION"
        message = "Moderate restless micro-motion detected."
        next_action = "OBSERVE_LONGER"

    if hand_score >= 25 and leg_score < 10:
        reason_code = "HAND_DOMINANT_MOTION"
        message = "Hand motion is dominant."
        next_action = "CHECK_HAND_REPETITION"

    elif leg_score >= 25 and hand_score < 10:
        reason_code = "LEG_DOMINANT_MOTION"
        message = "Leg motion is dominant."
        next_action = "CHECK_LEG_FIDGET"

    results.append({
        "track_id": track_id,
        "hand_motion_score": hand_score,
        "leg_fidget_score": leg_score,
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