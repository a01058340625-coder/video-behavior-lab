from ultralytics import YOLO
import csv
import os

VIDEO_PATH = "walk.mp4"
MODEL_PATH = "yolo11n.pt"
OUTPUT_DIR = "output"
CSV_PATH = os.path.join(OUTPUT_DIR, "tracks.csv")

os.makedirs(OUTPUT_DIR, exist_ok=True)

model = YOLO(MODEL_PATH)

results = model.track(
    source=VIDEO_PATH,
    persist=True,
    classes=[0],     # person only
    show=False,      # 화면창 끔
    save=True,       # 박스 그려진 결과 영상 저장
    stream=True      # 프레임별 결과를 순회
)

with open(CSV_PATH, "w", newline="", encoding="utf-8-sig") as f:
    writer = csv.writer(f)
    writer.writerow([
        "frame",
        "track_id",
        "x1",
        "y1",
        "x2",
        "y2",
        "conf"
    ])

    frame_no = 0

    for r in results:
        frame_no += 1

        if r.boxes is None or len(r.boxes) == 0:
            continue

        boxes = r.boxes.xyxy.cpu().tolist()
        confs = r.boxes.conf.cpu().tolist()

        if r.boxes.id is not None:
            ids = r.boxes.id.cpu().tolist()
        else:
            ids = [None] * len(boxes)

        for box, conf, track_id in zip(boxes, confs, ids):
            x1, y1, x2, y2 = box
            writer.writerow([
                frame_no,
                int(track_id) if track_id is not None else "",
                round(x1, 2),
                round(y1, 2),
                round(x2, 2),
                round(y2, 2),
                round(conf, 4)
            ])

print("DONE")
print(f"CSV saved: {CSV_PATH}")