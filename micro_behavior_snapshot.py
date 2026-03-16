# -*- coding: utf-8 -*-
import csv
import json

HAND_CSV = r"C:\dev\walk\pose_output\hand_motion_summary.csv"
LEG_CSV = r"C:\dev\walk\pose_output\leg_fidget_summary.csv"
POSTURE_CSV = r"C:\dev\walk\pose_output\posture_sway_summary.csv"
HAND_REP_CSV = r"C:\dev\walk\pose_output\hand_repetition_summary.csv"
LEG_REP_CSV = r"C:\dev\walk\pose_output\leg_repetition_summary.csv"
OUTPUT_JSON = r"C:\dev\walk\pose_output\micro_behavior_snapshot.json"

hand_map = {}
leg_map = {}
posture_map = {}
hand_rep_map = {}
leg_rep_map = {}

with open(HAND_CSV, "r", encoding="utf-8-sig") as f:
    reader = csv.DictReader(f)
    for row in reader:
        track_id = row["track_id"]
        hand_map[track_id] = {
            "hand_motion_score": float(row["hand_motion_score"]),
            "hand_motion_level": row["hand_motion_level"]
        }

with open(LEG_CSV, "r", encoding="utf-8-sig") as f:
    reader = csv.DictReader(f)
    for row in reader:
        track_id = row["track_id"]
        leg_map[track_id] = {
            "leg_fidget_score": float(row["leg_fidget_score"]),
            "leg_fidget_level": row["leg_fidget_level"]
        }

with open(POSTURE_CSV, "r", encoding="utf-8-sig") as f:
    reader = csv.DictReader(f)
    for row in reader:
        track_id = row["track_id"]
        posture_map[track_id] = {
            "posture_sway_score": float(row["posture_sway_score"]),
            "posture_sway_level": row["posture_sway_level"]
        }

with open(HAND_REP_CSV, "r", encoding="utf-8-sig") as f:
    reader = csv.DictReader(f)
    for row in reader:
        track_id = row["track_id"]
        hand_rep_map[track_id] = {
            "hand_repetition_score": float(row["hand_repetition_score"]),
            "hand_repetition_level": row["hand_repetition_level"]
        }

with open(LEG_REP_CSV, "r", encoding="utf-8-sig") as f:
    reader = csv.DictReader(f)
    for row in reader:
        track_id = row["track_id"]
        leg_rep_map[track_id] = {
            "leg_repetition_score": float(row["leg_repetition_score"]),
            "leg_repetition_level": row["leg_repetition_level"]
        }

all_track_ids = sorted(
    set(hand_map.keys())
    | set(leg_map.keys())
    | set(posture_map.keys())
    | set(hand_rep_map.keys())
    | set(leg_rep_map.keys()),
    key=int
)

tracks = []
for track_id in all_track_ids:
    hand = hand_map.get(track_id, {"hand_motion_score": 0.0, "hand_motion_level": "LOW"})
    leg = leg_map.get(track_id, {"leg_fidget_score": 0.0, "leg_fidget_level": "LOW"})
    posture = posture_map.get(track_id, {"posture_sway_score": 0.0, "posture_sway_level": "LOW"})
    hand_rep = hand_rep_map.get(track_id, {"hand_repetition_score": 0.0, "hand_repetition_level": "LOW"})
    leg_rep = leg_rep_map.get(track_id, {"leg_repetition_score": 0.0, "leg_repetition_level": "LOW"})

    micro_score = round(
        (
            hand["hand_motion_score"]
            + leg["leg_fidget_score"]
            + posture["posture_sway_score"]
            + hand_rep["hand_repetition_score"]
            + leg_rep["leg_repetition_score"]
        ) / 5,
        2
    )

    if micro_score >= 30:
        micro_level = "HIGH"
    elif micro_score >= 12:
        micro_level = "MEDIUM"
    else:
        micro_level = "LOW"

    tracks.append({
        "track_id": track_id,
        "hand_motion_score": hand["hand_motion_score"],
        "hand_motion_level": hand["hand_motion_level"],
        "leg_fidget_score": leg["leg_fidget_score"],
        "leg_fidget_level": leg["leg_fidget_level"],
        "posture_sway_score": posture["posture_sway_score"],
        "posture_sway_level": posture["posture_sway_level"],
        "hand_repetition_score": hand_rep["hand_repetition_score"],
        "hand_repetition_level": hand_rep["hand_repetition_level"],
        "leg_repetition_score": leg_rep["leg_repetition_score"],
        "leg_repetition_level": leg_rep["leg_repetition_level"],
        "micro_behavior_score": micro_score,
        "micro_behavior_level": micro_level
    })

snapshot = {
    "video": "walk.mp4",
    "track_count": len(tracks),
    "tracks": tracks
}

with open(OUTPUT_JSON, "w", encoding="utf-8-sig") as f:
    json.dump(snapshot, f, ensure_ascii=False, indent=2)

print("DONE")
print(f"Micro snapshot saved: {OUTPUT_JSON}")
print(json.dumps(snapshot, ensure_ascii=False, indent=2))