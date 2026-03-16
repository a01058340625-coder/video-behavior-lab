# -*- coding: utf-8 -*-
import csv

INPUT_CSV = r"C:\dev\walk\output\summary.csv"
OUTPUT_CSV = r"C:\dev\walk\output\behavior.csv"

rows = []

with open(INPUT_CSV, "r", encoding="utf-8-sig") as f:
    reader = csv.DictReader(f)
    for row in reader:
        track_id = row["track_id"]
        duration_frames = int(row["duration_frames"])
        points = int(row["points"])
        total_distance = float(row["total_distance"])
        avg_step_distance = float(row["avg_step_distance"])

        # 1�� ��Ģ �з�
        if points < 3 or duration_frames < 5:
            behavior_type = "noise"
        elif avg_step_distance > 30:
            behavior_type = "tracking_noise"
        elif duration_frames >= 200 and avg_step_distance >= 8:
            behavior_type = "active_walker"
        elif duration_frames >= 150 and avg_step_distance < 8:
            behavior_type = "slow_mover"
        elif duration_frames < 80:
            behavior_type = "passerby"
        else:
            behavior_type = "walker"

        rows.append({
            "track_id": track_id,
            "duration_frames": duration_frames,
            "points": points,
            "total_distance": round(total_distance, 2),
            "avg_step_distance": round(avg_step_distance, 2),
            "behavior_type": behavior_type
        })

with open(OUTPUT_CSV, "w", newline="", encoding="utf-8-sig") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "track_id",
            "duration_frames",
            "points",
            "total_distance",
            "avg_step_distance",
            "behavior_type"
        ]
    )
    writer.writeheader()
    writer.writerows(rows)

print("DONE")
print(f"Behavior saved: {OUTPUT_CSV}")
for row in rows:
    print(row)