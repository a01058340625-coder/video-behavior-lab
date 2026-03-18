# -*- coding: utf-8 -*-
import json

INPUT_JSON = r"C:\dev\loosegoose\walk\pose_output\behavior_snapshot.json"
OUTPUT_JSON = r"C:\dev\loosegoose\walk\pose_output\behavior_judgment.json"

with open(INPUT_JSON, "r", encoding="utf-8-sig") as f:
    snapshot = json.load(f)

results = []

for track in snapshot.get("tracks", []):
    track_id = track["track_id"]
    hand_score = float(track["hand_motion_score"])
    leg_score = float(track["leg_motion_score"])
    behavior_score = float(track["behavior_score"])

    state = "STABLE"
    reason_code = "LOW_TOTAL_MOTION"
    message = "Overall motion is low and stable."
    next_action = "CONTINUE_MONITORING"

    if hand_score >= 20 and leg_score >= 20:
        state = "RESTLESS"
        reason_code = "HIGH_HAND_AND_LEG_MOTION"
        message = "Both hand and leg motion are elevated."
        next_action = "CHECK_FULL_BODY_PATTERN"

    elif hand_score >= 20:
        state = "HAND_ACTIVE"
        reason_code = "HIGH_HAND_MOTION"
        message = "Hand motion is elevated."
        next_action = "CHECK_HAND_PATTERN"

    elif leg_score >= 12:
        state = "LEG_ACTIVE"
        reason_code = "HIGH_LEG_MOTION"
        message = "Leg motion is elevated."
        next_action = "CHECK_LEG_PATTERN"

    elif behavior_score >= 8:
        state = "MILD_ACTIVITY"
        reason_code = "MEDIUM_TOTAL_MOTION"
        message = "Moderate overall motion detected."
        next_action = "OBSERVE_LONGER"

    results.append({
        "track_id": track_id,
        "hand_motion_score": hand_score,
        "leg_motion_score": leg_score,
        "behavior_score": behavior_score,
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
print(f"Behavior judgment saved: {OUTPUT_JSON}")
print(json.dumps(output, ensure_ascii=False, indent=2))