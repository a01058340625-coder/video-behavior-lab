# -*- coding: utf-8 -*-
import csv
import json

INPUT_CSV = r"C:\dev\loosegoose\walk\output\behavior.csv"
OUTPUT_JSON = r"C:\dev\loosegoose\walk\output\session_snapshot.json"

rows = []

with open(INPUT_CSV, "r", encoding="utf-8-sig") as f:
    reader = csv.DictReader(f)
    for row in reader:
        row["duration_frames"] = int(row["duration_frames"])
        row["points"] = int(row["points"])
        row["total_distance"] = float(row["total_distance"])
        row["avg_step_distance"] = float(row["avg_step_distance"])
        rows.append(row)

total_tracks = len(rows)

active_walker_count = sum(1 for r in rows if r["behavior_type"] == "active_walker")
slow_mover_count = sum(1 for r in rows if r["behavior_type"] == "slow_mover")
walker_count = sum(1 for r in rows if r["behavior_type"] == "walker")
passerby_count = sum(1 for r in rows if r["behavior_type"] == "passerby")
tracking_noise_count = sum(1 for r in rows if r["behavior_type"] == "tracking_noise")
noise_count = sum(1 for r in rows if r["behavior_type"] == "noise")

avg_duration_frames = round(
    sum(r["duration_frames"] for r in rows) / total_tracks, 2
) if total_tracks else 0

avg_total_distance = round(
    sum(r["total_distance"] for r in rows) / total_tracks, 2
) if total_tracks else 0

max_total_distance = round(
    max((r["total_distance"] for r in rows), default=0), 2
)

snapshot = {
    "video": "walk.mp4",
    "total_tracks": total_tracks,
    "counts": {
        "active_walker": active_walker_count,
        "slow_mover": slow_mover_count,
        "walker": walker_count,
        "passerby": passerby_count,
        "tracking_noise": tracking_noise_count,
        "noise": noise_count
    },
    "metrics": {
        "avg_duration_frames": avg_duration_frames,
        "avg_total_distance": avg_total_distance,
        "max_total_distance": max_total_distance
    }
}

with open(OUTPUT_JSON, "w", encoding="utf-8-sig") as f:
    json.dump(snapshot, f, ensure_ascii=False, indent=2)

print("DONE")
print(f"Snapshot saved: {OUTPUT_JSON}")
print(json.dumps(snapshot, ensure_ascii=False, indent=2))