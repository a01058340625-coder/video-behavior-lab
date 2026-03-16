# -*- coding: utf-8 -*-
import csv
import math
from collections import defaultdict

INPUT_CSV = r"C:\dev\walk\pose_output\pose_keypoints.csv"
OUTPUT_CSV = r"C:\dev\walk\pose_output\hand_motion_summary.csv"

# COCO keypoints
LEFT_WRIST = 9
RIGHT_WRIST = 10

# track_id별, frame별 손목 좌표 저장
# tracks[track_id][frame][kp_index] = (x, y, conf)
tracks = defaultdict(lambda: defaultdict(dict))

with open(INPUT_CSV, "r", encoding="utf-8-sig") as f:
    reader = csv.DictReader(f)
    for row in reader:
        frame = int(row["frame"])
        track_id = row["track_id"].strip()
        kp_index = int(row["kp_index"])
        x = float(row["x"])
        y = float(row["y"])

        visible_raw = str(row["visible"]).strip()
        conf = float(visible_raw) if visible_raw else 0.0

        if kp_index in (LEFT_WRIST, RIGHT_WRIST):
            tracks[track_id][frame][kp_index] = (x, y, conf)

summary_rows = []

for track_id, frames_dict in tracks.items():
    frames = sorted(frames_dict.keys())

    left_total = 0.0
    right_total = 0.0
    left_steps = 0
    right_steps = 0

    prev_left = None
    prev_right = None

    for frame in frames:
        kp_map = frames_dict[frame]

        # 왼손
        if LEFT_WRIST in kp_map:
            x, y, conf = kp_map[LEFT_WRIST]
            if conf >= 0.5:
                if prev_left is not None:
                    dist = math.hypot(x - prev_left[0], y - prev_left[1])
                    left_total += dist
                    left_steps += 1
                prev_left = (x, y)

        # 오른손
        if RIGHT_WRIST in kp_map:
            x, y, conf = kp_map[RIGHT_WRIST]
            if conf >= 0.5:
                if prev_right is not None:
                    dist = math.hypot(x - prev_right[0], y - prev_right[1])
                    right_total += dist
                    right_steps += 1
                prev_right = (x, y)

    left_avg = left_total / left_steps if left_steps > 0 else 0.0
    right_avg = right_total / right_steps if right_steps > 0 else 0.0

    hand_motion_score = (left_avg + right_avg) / 2

    if hand_motion_score >= 25:
        hand_motion_level = "HIGH"
    elif hand_motion_score >= 10:
        hand_motion_level = "MEDIUM"
    else:
        hand_motion_level = "LOW"

    summary_rows.append({
        "track_id": track_id,
        "left_total_motion": round(left_total, 2),
        "right_total_motion": round(right_total, 2),
        "left_avg_motion": round(left_avg, 2),
        "right_avg_motion": round(right_avg, 2),
        "hand_motion_score": round(hand_motion_score, 2),
        "hand_motion_level": hand_motion_level
    })

summary_rows.sort(key=lambda x: int(x["track_id"]))

with open(OUTPUT_CSV, "w", newline="", encoding="utf-8-sig") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "track_id",
            "left_total_motion",
            "right_total_motion",
            "left_avg_motion",
            "right_avg_motion",
            "hand_motion_score",
            "hand_motion_level"
        ]
    )
    writer.writeheader()
    writer.writerows(summary_rows)

print("DONE")
print(f"Hand motion saved: {OUTPUT_CSV}")
for row in summary_rows:
    print(row)