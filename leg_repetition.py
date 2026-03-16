# -*- coding: utf-8 -*-
import csv
from collections import defaultdict

INPUT_CSV = r"C:\dev\walk\pose_output\pose_keypoints.csv"
OUTPUT_CSV = r"C:\dev\walk\pose_output\leg_repetition_summary.csv"

LEFT_KNEE = 13
RIGHT_KNEE = 14
LEFT_ANKLE = 15
RIGHT_ANKLE = 16
TARGETS = [LEFT_KNEE, RIGHT_KNEE, LEFT_ANKLE, RIGHT_ANKLE]

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

        if kp_index in TARGETS and conf >= 0.5:
            tracks[track_id][frame][kp_index] = (x, y)

summary_rows = []

for track_id, frames_dict in tracks.items():
    frames = sorted(frames_dict.keys())

    rep_counts = {kp: 0 for kp in TARGETS}
    step_counts = {kp: 0 for kp in TARGETS}

    history = {kp: [] for kp in TARGETS}

    for frame in frames:
        kp_map = frames_dict[frame]

        for kp in TARGETS:
            if kp not in kp_map:
                continue
            x, y = kp_map[kp]
            history[kp].append((frame, x, y))

    for kp in TARGETS:
        points = history[kp]

        for i in range(2, len(points)):
            _, x1, y1 = points[i - 2]
            _, x2, y2 = points[i - 1]
            _, x3, y3 = points[i]

            dx1 = x2 - x1
            dx2 = x3 - x2
            dy1 = y2 - y1
            dy2 = y3 - y2

            step_counts[kp] += 1

            x_flip = (dx1 > 0 and dx2 < 0) or (dx1 < 0 and dx2 > 0)
            y_flip = (dy1 > 0 and dy2 < 0) or (dy1 < 0 and dy2 > 0)

            small_motion = (
                abs(dx1) < 25 and abs(dx2) < 25 and
                abs(dy1) < 25 and abs(dy2) < 25
            )

            if small_motion and (x_flip or y_flip):
                rep_counts[kp] += 1

    ratios = {}
    for kp in TARGETS:
        ratios[kp] = rep_counts[kp] / step_counts[kp] if step_counts[kp] > 0 else 0.0

    leg_repetition_score = round((sum(ratios.values()) / len(TARGETS)) * 100, 2)

    if leg_repetition_score >= 35:
        leg_repetition_level = "HIGH"
    elif leg_repetition_score >= 15:
        leg_repetition_level = "MEDIUM"
    else:
        leg_repetition_level = "LOW"

    summary_rows.append({
        "track_id": track_id,
        "left_knee_repetition_ratio": round(ratios[LEFT_KNEE], 4),
        "right_knee_repetition_ratio": round(ratios[RIGHT_KNEE], 4),
        "left_ankle_repetition_ratio": round(ratios[LEFT_ANKLE], 4),
        "right_ankle_repetition_ratio": round(ratios[RIGHT_ANKLE], 4),
        "leg_repetition_score": leg_repetition_score,
        "leg_repetition_level": leg_repetition_level
    })

summary_rows.sort(key=lambda x: int(x["track_id"]))

with open(OUTPUT_CSV, "w", newline="", encoding="utf-8-sig") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "track_id",
            "left_knee_repetition_ratio",
            "right_knee_repetition_ratio",
            "left_ankle_repetition_ratio",
            "right_ankle_repetition_ratio",
            "leg_repetition_score",
            "leg_repetition_level"
        ]
    )
    writer.writeheader()
    writer.writerows(summary_rows)

print("DONE")
print(f"Leg repetition saved: {OUTPUT_CSV}")
for row in summary_rows:
    print(row)