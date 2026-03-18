# -*- coding: utf-8 -*-
import csv
import math
from collections import defaultdict

INPUT_CSV = r"C:\dev\loosegoose\walk\pose_output\pose_keypoints.csv"
OUTPUT_CSV = r"C:\dev\loosegoose\walk\pose_output\leg_fidget_summary.csv"

# COCO keypoints
LEFT_KNEE = 13
RIGHT_KNEE = 14
LEFT_ANKLE = 15
RIGHT_ANKLE = 16

LEG_POINTS = [LEFT_KNEE, RIGHT_KNEE, LEFT_ANKLE, RIGHT_ANKLE]

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

        if kp_index in LEG_POINTS:
            tracks[track_id][frame][kp_index] = (x, y, conf)

summary_rows = []

for track_id, frames_dict in tracks.items():
    frames = sorted(frames_dict.keys())

    totals = {kp: 0.0 for kp in LEG_POINTS}
    steps = {kp: 0 for kp in LEG_POINTS}
    prevs = {kp: None for kp in LEG_POINTS}

    for frame in frames:
        kp_map = frames_dict[frame]

        for kp in LEG_POINTS:
            if kp not in kp_map:
                continue

            x, y, conf = kp_map[kp]
            if conf < 0.5:
                continue

            if prevs[kp] is not None:
                dist = math.hypot(x - prevs[kp][0], y - prevs[kp][1])
                totals[kp] += dist
                steps[kp] += 1

            prevs[kp] = (x, y)

    avgs = {}
    for kp in LEG_POINTS:
        avgs[kp] = totals[kp] / steps[kp] if steps[kp] > 0 else 0.0

    leg_fidget_score = sum(avgs.values()) / len(LEG_POINTS)

    if leg_fidget_score >= 25:
        leg_fidget_level = "HIGH"
    elif leg_fidget_score >= 10:
        leg_fidget_level = "MEDIUM"
    else:
        leg_fidget_level = "LOW"

    summary_rows.append({
        "track_id": track_id,
        "left_knee_avg_motion": round(avgs[LEFT_KNEE], 2),
        "right_knee_avg_motion": round(avgs[RIGHT_KNEE], 2),
        "left_ankle_avg_motion": round(avgs[LEFT_ANKLE], 2),
        "right_ankle_avg_motion": round(avgs[RIGHT_ANKLE], 2),
        "leg_fidget_score": round(leg_fidget_score, 2),
        "leg_fidget_level": leg_fidget_level
    })

summary_rows.sort(key=lambda x: int(x["track_id"]))

with open(OUTPUT_CSV, "w", newline="", encoding="utf-8-sig") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "track_id",
            "left_knee_avg_motion",
            "right_knee_avg_motion",
            "left_ankle_avg_motion",
            "right_ankle_avg_motion",
            "leg_fidget_score",
            "leg_fidget_level"
        ]
    )
    writer.writeheader()
    writer.writerows(summary_rows)

print("DONE")
print(f"Leg fidget saved: {OUTPUT_CSV}")
for row in summary_rows:
    print(row)