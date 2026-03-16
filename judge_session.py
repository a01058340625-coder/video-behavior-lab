import json

INPUT_JSON = r"C:\dev\walk\output\session_snapshot.json"
OUTPUT_JSON = r"C:\dev\walk\output\session_judgment.json"

with open(INPUT_JSON, "r", encoding="utf-8-sig") as f:
    snapshot = json.load(f)

counts = snapshot["counts"]
metrics = snapshot["metrics"]

active_walker = counts["active_walker"]
slow_mover = counts["slow_mover"]
walker = counts["walker"]
passerby = counts["passerby"]
tracking_noise = counts["tracking_noise"]
noise = counts["noise"]

total_tracks = snapshot["total_tracks"]
avg_duration = metrics["avg_duration_frames"]
avg_distance = metrics["avg_total_distance"]
max_distance = metrics["max_total_distance"]

state = "NORMAL_FLOW"
reason_code = "DEFAULT_FLOW"
message = "Pedestrian flow appears normal."

if tracking_noise + noise >= 3:
    state = "NOISY_SESSION"
    reason_code = "TOO_MUCH_NOISE"
    message = "Too much detection noise."

elif active_walker == 0 and walker == 0 and slow_mover == 0:
    state = "LOW_ACTIVITY"
    reason_code = "NO_MEANINGFUL_MOTION"
    message = "No meaningful pedestrian activity."

elif slow_mover >= 2 and active_walker == 0:
    state = "SLOW_FLOW"
    reason_code = "MOSTLY_SLOW_MOVERS"
    message = "Mostly slow pedestrian movement."

elif active_walker >= 1 and max_distance >= 2000:
    state = "ACTIVE_FLOW"
    reason_code = "CLEAR_MAIN_WALKER"
    message = "Clear active pedestrian detected."

judgment = {
    "video": snapshot["video"],
    "snapshot": snapshot,
    "judgment": {
        "state": state,
        "reason_code": reason_code,
        "message": message
    }
}

with open(OUTPUT_JSON, "w", encoding="utf-8-sig") as f:
    json.dump(judgment, f, ensure_ascii=False, indent=2)

print("DONE")
print(f"Judgment saved: {OUTPUT_JSON}")
print(json.dumps(judgment, ensure_ascii=False, indent=2))