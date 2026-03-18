# -*- coding: utf-8 -*-
import csv
import json

HAND_CSV = r"C:\dev\loosegoose\walk\pose_output\hand_motion_summary.csv"
LEG_CSV = r"C:\dev\loosegoose\walk\pose_output\leg_motion_summary.csv"
OUTPUT_JSON = r"C:\dev\loosegoose\walk\pose_output\behavior_snapshot.json"


def safe_float(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


def level_from_score(score):
    if score >= 25:
        return "HIGH"
    elif score >= 8:
        return "MEDIUM"
    return "LOW"


hand_map = {}
leg_map = {}

with open(HAND_CSV, "r", encoding="utf-8-sig") as f:
    reader = csv.DictReader(f)
    for row in reader:
        track_id = row["track_id"]
        hand_map[track_id] = {
            "hand_motion_score": safe_float(row.get("hand_motion_score", 0)),
            "hand_motion_level": row.get("hand_motion_level", "LOW"),
        }

with open(LEG_CSV, "r", encoding="utf-8-sig") as f:
    reader = csv.DictReader(f)
    for row in reader:
        track_id = row["track_id"]
        leg_map[track_id] = {
            "leg_motion_score": safe_float(row.get("leg_motion_score", 0)),
            "leg_motion_level": row.get("leg_motion_level", "LOW"),
        }

all_track_ids = sorted(set(hand_map.keys()) | set(leg_map.keys()), key=int)

tracks = []

for track_id in all_track_ids:
    hand = hand_map.get(track_id, {
        "hand_motion_score": 0.0,
        "hand_motion_level": "LOW",
    })
    leg = leg_map.get(track_id, {
        "leg_motion_score": 0.0,
        "leg_motion_level": "LOW",
    })

    behavior_score = round(
        (hand["hand_motion_score"] + leg["leg_motion_score"]) / 2,
        2
    )
    behavior_level = level_from_score(behavior_score)

    tracks.append({
        "track_id": track_id,
        "hand_motion_score": hand["hand_motion_score"],
        "hand_motion_level": hand["hand_motion_level"],
        "leg_motion_score": leg["leg_motion_score"],
        "leg_motion_level": leg["leg_motion_level"],
        "behavior_score": behavior_score,
        "behavior_level": behavior_level,
    })

snapshot = {
    "video": "walk.mp4",
    "track_count": len(tracks),
    "tracks": tracks
}

with open(OUTPUT_JSON, "w", encoding="utf-8-sig") as f:
    json.dump(snapshot, f, ensure_ascii=False, indent=2)

print("DONE")
print(f"Behavior snapshot saved: {OUTPUT_JSON}")
print(json.dumps(snapshot, ensure_ascii=False, indent=2))