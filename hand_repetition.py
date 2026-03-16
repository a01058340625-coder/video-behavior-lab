# -*- coding: utf-8 -*-
import csv
from collections import defaultdict

INPUT_CSV = r"C:\dev\walk\pose_output\pose_keypoints.csv"
OUTPUT_CSV = r"C:\dev\walk\pose_output\hand_repetition_summary.csv"

LEFT_WRIST = 9
RIGHT_WRIST = 10
TARGETS = [LEFT_WRIST, RIGHT_WRIST]

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

    rep_counts = {LEFT_WRIST: 0, RIGHT_WRIST: 0}
    step_counts = {LEFT_WRIST: 0, RIGHT_WRIST: 0}

    history = {
        LEFT_WRIST: [],
        RIGHT_WRIST: []
    }

    for frame in frames:
        kp_map = frames_dict[frame]

        for kp in TARGETS:
            if kp not in kp_map:
                continue

            x, y = kp_map[kp]
            history[kp].append((frame, x, y))

    for kp in TARGETS:
        points = history[kp]

        # 최근 3개 점으로 x방향 전환 반복을 본다
        for i in range(2, len(points)):
            _, x1, y1 = points[i - 2]
            _, x2, y2 = points[i - 1]
            _, x3, y3 = points[i]

            dx1 = x2 - x1
            dx2 = x3 - x2
            dy1 = y2 - y1
            dy2 = y3 - y2

            step_counts[kp] += 1

            # 작은 범위 안에서 방향이 바뀌면 repetition 후보
            x_flip = (dx1 > 0 and dx2 < 0) or (dx1 < 0 and dx2 > 0)
            y_flip = (dy1 > 0 and dy2 < 0) or (dy1 < 0 and dy2 > 0)

            small_motion = (
                abs(dx1) < 30 and abs(dx2) < 30 and
                abs(dy1) < 30 and abs(dy2) < 30
            )

            if small_motion and (x_flip or y_flip):
                rep_counts[kp] += 1

    left_ratio = rep_counts[LEFT_WRIST] / step_counts[LEFT_WRIST] if step_counts[LEFT_WRIST] > 0 else 0.0
    right_ratio = rep_counts[RIGHT_WRIST] / step_counts[RIGHT_WRIST] if step_counts[RIGHT_WRIST] > 0 else 0.0

    hand_repetition_score = round(((left_ratio + right_ratio) / 2) * 100, 2)

    if hand_repetition_score >= 35:
        hand_repetition_level = "HIGH"
    elif hand_repetition_score >= 15:
        hand_repetition_level = "MEDIUM"
    else:
        hand_repetition_level = "LOW"

    summary_rows.append({
        "track_id": track_id,
        "left_repetition_ratio": round(left_ratio, 4),
        "right_repetition_ratio": round(right_ratio, 4),
        "hand_repetition_score": hand_repetition_score,
        "hand_repetition_level": hand_repetition_level
    })

summary_rows.sort(key=lambda x: int(x["track_id"]))

with open(OUTPUT_CSV, "w", newline="", encoding="utf-8-sig") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "track_id",
            "left_repetition_ratio",
            "right_repetition_ratio",
            "hand_repetition_score",
            "hand_repetition_level"
        ]
    )
    writer.writeheader()
    writer.writerows(summary_rows)

print("DONE")
print(f"Hand repetition saved: {OUTPUT_CSV}")
for row in summary_rows:
    print(row)