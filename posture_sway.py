# -*- coding: utf-8 -*-
import csv
import math
from collections import defaultdict

INPUT_CSV = r"C:\dev\loosegoose\walk\pose_output\pose_keypoints.csv"
OUTPUT_CSV = r"C:\dev\loosegoose\walk\pose_output\posture_sway_summary.csv"

# COCO keypoints
LEFT_SHOULDER = 5
RIGHT_SHOULDER = 6
LEFT_HIP = 11
RIGHT_HIP = 12

TORSO_POINTS = [LEFT_SHOULDER, RIGHT_SHOULDER, LEFT_HIP, RIGHT_HIP]

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

        if kp_index in TORSO_POINTS:
            tracks[track_id][frame][kp_index] = (x, y, conf)

summary_rows = []

for track_id, frames_dict in tracks.items():
    frames = sorted(frames_dict.keys())

    prev_center = None
    total_sway = 0.0
    sway_steps = 0

    x_moves = []
    y_moves = []

    for frame in frames:
        kp_map = frames_dict[frame]

        valid_points = []
        for kp in TORSO_POINTS:
            if kp not in kp_map:
                continue

            x, y, conf = kp_map[kp]
            if conf >= 0.5:
                valid_points.append((x, y))

        # ���� �߽��� �������� �ּ� 2�� �̻��� �־�� �Ѵ�
        if len(valid_points) < 2:
            continue

        cx = sum(p[0] for p in valid_points) / len(valid_points)
        cy = sum(p[1] for p in valid_points) / len(valid_points)

        if prev_center is not None:
            dx = cx - prev_center[0]
            dy = cy - prev_center[1]
            dist = math.hypot(dx, dy)

            total_sway += dist
            sway_steps += 1
            x_moves.append(abs(dx))
            y_moves.append(abs(dy))

        prev_center = (cx, cy)

    avg_sway = total_sway / sway_steps if sway_steps > 0 else 0.0
    avg_x_sway = sum(x_moves) / len(x_moves) if x_moves else 0.0
    avg_y_sway = sum(y_moves) / len(y_moves) if y_moves else 0.0

    posture_sway_score = avg_sway

    if posture_sway_score >= 20:
        posture_sway_level = "HIGH"
    elif posture_sway_score >= 8:
        posture_sway_level = "MEDIUM"
    else:
        posture_sway_level = "LOW"

    summary_rows.append({
        "track_id": track_id,
        "avg_sway": round(avg_sway, 2),
        "avg_x_sway": round(avg_x_sway, 2),
        "avg_y_sway": round(avg_y_sway, 2),
        "posture_sway_score": round(posture_sway_score, 2),
        "posture_sway_level": posture_sway_level
    })

summary_rows.sort(key=lambda x: int(x["track_id"]))

with open(OUTPUT_CSV, "w", newline="", encoding="utf-8-sig") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "track_id",
            "avg_sway",
            "avg_x_sway",
            "avg_y_sway",
            "posture_sway_score",
            "posture_sway_level"
        ]
    )
    writer.writeheader()
    writer.writerows(summary_rows)

print("DONE")
print(f"Posture sway saved: {OUTPUT_CSV}")
for row in summary_rows:
    print(row)