# -*- coding: utf-8 -*-
import csv
import math
from collections import defaultdict

INPUT_CSV = r"C:\dev\loosegoose\walk\pose_output\pose_keypoints.csv"
OUTPUT_CSV = r"C:\dev\loosegoose\walk\pose_output\leg_motion_summary.csv"

LEFT_KNEE = 13
RIGHT_KNEE = 14
LEFT_ANKLE = 15
RIGHT_ANKLE = 16


def safe_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def dist(x1, y1, x2, y2):
    return math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2)


def level_from_score(score):
    if score >= 25:
        return "HIGH"
    elif score >= 8:
        return "MEDIUM"
    return "LOW"


# ����:
# track_id -> frame -> kp_index -> (x, y, visible)
tracks = defaultdict(lambda: defaultdict(dict))

with open(INPUT_CSV, "r", encoding="utf-8-sig") as f:
    reader = csv.DictReader(f)
    for row in reader:
        frame = int(safe_float(row.get("frame", 0)))
        track_id = str(row.get("track_id", "")).strip()
        kp_index = int(safe_float(row.get("kp_index", -1)))
        x = safe_float(row.get("x", 0))
        y = safe_float(row.get("y", 0))
        visible = safe_float(row.get("visible", 0))

        tracks[track_id][frame][kp_index] = (x, y, visible)

results = []

for track_id, frames_map in tracks.items():
    frame_numbers = sorted(frames_map.keys())

    left_knee_total = 0.0
    right_knee_total = 0.0
    left_ankle_total = 0.0
    right_ankle_total = 0.0

    left_knee_count = 0
    right_knee_count = 0
    left_ankle_count = 0
    right_ankle_count = 0

    for i in range(1, len(frame_numbers)):
        prev_frame = frame_numbers[i - 1]
        curr_frame = frame_numbers[i]

        prev_points = frames_map[prev_frame]
        curr_points = frames_map[curr_frame]

        for kp_idx, part_name in [
            (LEFT_KNEE, "left_knee"),
            (RIGHT_KNEE, "right_knee"),
            (LEFT_ANKLE, "left_ankle"),
            (RIGHT_ANKLE, "right_ankle"),
        ]:
            if kp_idx not in prev_points or kp_idx not in curr_points:
                continue

            x1, y1, v1 = prev_points[kp_idx]
            x2, y2, v2 = curr_points[kp_idx]

            if v1 < 0.3 or v2 < 0.3:
                continue

            motion = dist(x1, y1, x2, y2)

            if part_name == "left_knee":
                left_knee_total += motion
                left_knee_count += 1
            elif part_name == "right_knee":
                right_knee_total += motion
                right_knee_count += 1
            elif part_name == "left_ankle":
                left_ankle_total += motion
                left_ankle_count += 1
            elif part_name == "right_ankle":
                right_ankle_total += motion
                right_ankle_count += 1

    left_knee_avg = round(left_knee_total / left_knee_count, 2) if left_knee_count else 0.0
    right_knee_avg = round(right_knee_total / right_knee_count, 2) if right_knee_count else 0.0
    left_ankle_avg = round(left_ankle_total / left_ankle_count, 2) if left_ankle_count else 0.0
    right_ankle_avg = round(right_ankle_total / right_ankle_count, 2) if right_ankle_count else 0.0

    leg_motion_score = round(
        (left_knee_avg + right_knee_avg + left_ankle_avg + right_ankle_avg) / 4,
        2
    )
    leg_motion_level = level_from_score(leg_motion_score)

    results.append({
        "track_id": track_id,
        "left_knee_avg_motion": left_knee_avg,
        "right_knee_avg_motion": right_knee_avg,
        "left_ankle_avg_motion": left_ankle_avg,
        "right_ankle_avg_motion": right_ankle_avg,
        "leg_motion_score": leg_motion_score,
        "leg_motion_level": leg_motion_level,
    })

results.sort(key=lambda r: int(r["track_id"]))

with open(OUTPUT_CSV, "w", newline="", encoding="utf-8-sig") as f:
    fieldnames = [
        "track_id",
        "left_knee_avg_motion",
        "right_knee_avg_motion",
        "left_ankle_avg_motion",
        "right_ankle_avg_motion",
        "leg_motion_score",
        "leg_motion_level",
    ]
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(results)

print("DONE")
print(f"Leg motion saved: {OUTPUT_CSV}")
for row in results:
    print(row)