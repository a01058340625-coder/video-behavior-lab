# -*- coding: utf-8 -*-
from ultralytics import YOLO
import csv
import os

VIDEO_PATH = "walk.mp4"
MODEL_PATH = "yolo11n-pose.pt"
OUTPUT_DIR = "pose_output"
CSV_PATH = os.path.join(OUTPUT_DIR, "pose_keypoints.csv")

os.makedirs(OUTPUT_DIR, exist_ok=True)

model = YOLO(MODEL_PATH)

results = model.track(
    source=VIDEO_PATH,
    persist=True,
    classes=[0],   # person only
    show=False,
    save=True,
    stream=True
)

with open(CSV_PATH, "w", newline="", encoding="utf-8-sig") as f:
    writer = csv.writer(f)
    writer.writerow([
        "frame",
        "track_id",
        "kp_index",
        "x",
        "y",
        "visible"
    ])

    frame_no = 0

    for r in results:
        frame_no += 1

        if r.boxes is None or len(r.boxes) == 0:
            continue

        if r.keypoints is None:
            continue

        if r.boxes.id is not None:
            ids = r.boxes.id.cpu().tolist()
        else:
            ids = [None] * len(r.boxes)

        kps_xy = r.keypoints.xy.cpu().tolist()

        if hasattr(r.keypoints, "conf") and r.keypoints.conf is not None:
            kps_conf = r.keypoints.conf.cpu().tolist()
        else:
            kps_conf = None

        for person_idx, person_kps in enumerate(kps_xy):
            track_id = ids[person_idx]
            if track_id is None:
                continue

            for kp_index, (x, y) in enumerate(person_kps):
                visible = ""
                if kps_conf is not None:
                    visible = round(kps_conf[person_idx][kp_index], 4)

                writer.writerow([
                    frame_no,
                    int(track_id),
                    kp_index,
                    round(x, 2),
                    round(y, 2),
                    visible
                ])

print("DONE")
print(f"Pose CSV saved: {CSV_PATH}")