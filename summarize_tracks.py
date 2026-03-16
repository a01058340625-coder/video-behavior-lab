import csv
import math
from collections import defaultdict

INPUT_CSV = r"C:\dev\walk\output\tracks.csv"
OUTPUT_CSV = r"C:\dev\walk\output\summary.csv"

tracks = defaultdict(list)

with open(INPUT_CSV, "r", encoding="utf-8-sig") as f:
    reader = csv.DictReader(f)
    for row in reader:
        track_id = row["track_id"].strip()
        if not track_id:
            continue

        frame = int(row["frame"])
        x1 = float(row["x1"])
        y1 = float(row["y1"])
        x2 = float(row["x2"])
        y2 = float(row["y2"])

        cx = (x1 + x2) / 2
        cy = (y1 + y2) / 2

        tracks[track_id].append((frame, cx, cy))

summary_rows = []

for track_id, points in tracks.items():
    points.sort(key=lambda x: x[0])

    start_frame = points[0][0]
    end_frame = points[-1][0]
    duration_frames = end_frame - start_frame + 1

    total_distance = 0.0
    for i in range(1, len(points)):
        _, x_prev, y_prev = points[i - 1]
        _, x_now, y_now = points[i]
        dist = math.hypot(x_now - x_prev, y_now - y_prev)
        total_distance += dist

    avg_step_distance = total_distance / max(len(points) - 1, 1)

    summary_rows.append({
        "track_id": track_id,
        "start_frame": start_frame,
        "end_frame": end_frame,
        "duration_frames": duration_frames,
        "points": len(points),
        "total_distance": round(total_distance, 2),
        "avg_step_distance": round(avg_step_distance, 2),
    })

summary_rows.sort(key=lambda x: int(x["track_id"]))

with open(OUTPUT_CSV, "w", newline="", encoding="utf-8-sig") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "track_id",
            "start_frame",
            "end_frame",
            "duration_frames",
            "points",
            "total_distance",
            "avg_step_distance",
        ],
    )
    writer.writeheader()
    writer.writerows(summary_rows)

print("DONE")
print(f"Summary saved: {OUTPUT_CSV}")
for row in summary_rows:
    print(row)