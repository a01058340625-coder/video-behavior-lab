import json
import requests
from collections import Counter

BASE_URL = "http://127.0.0.1:8083"
INTERNAL_KEY = "goosage-dev"
USER_ID = 5
INPUT_FILE = "pose_output/micro_behavior_judgment.json"
TIMEOUT = 5

STATE_TO_EVENT = {
    "STABLE": "QUIZ_SUBMIT",
    "MULTI_REPETITIVE_SIGNAL": "REVIEW_WRONG",
    "HIGH_MOTION": "REVIEW_WRONG",
    "HIGH_MICRO_MOTION": "JUST_OPEN",
    "RESTLESS": "JUST_OPEN",
    "REPEATED": "JUST_OPEN",
    "IDLE": "JUST_OPEN",
    "NO_ACTIVITY": "JUST_OPEN",
}

STATE_TO_WEIGHT = {
    "STABLE": 1,
    "MULTI_REPETITIVE_SIGNAL": 1,
    "HIGH_MOTION": 2,
    "HIGH_MICRO_MOTION": 2,
    "RESTLESS": 1,
    "REPEATED": 1,
    "IDLE": 1,
    "NO_ACTIVITY": 1,
}

REASON_TO_EXTRA_WEIGHT = {
    "STRONG_RESTLESS_SIGNAL": 1,
    "HIGH_POSTURE_SWAY": 1,
    "MEDIUM_MICRO_MOTION": 0,
}

DEFAULT_EVENT = "JUST_OPEN"
DEFAULT_WEIGHT = 1


def map_state_to_event(state: str) -> str:
    return STATE_TO_EVENT.get(state, DEFAULT_EVENT)


def map_state_to_weight(state: str) -> int:
    return STATE_TO_WEIGHT.get(state, DEFAULT_WEIGHT)


def get_extra_weight(reason_code: str) -> int:
    return REASON_TO_EXTRA_WEIGHT.get(reason_code, 0)


def post_event(session: requests.Session, user_id: int, event_type: str) -> tuple[int, str]:
    payload = {
        "userId": user_id,
        "type": event_type
    }

    res = session.post(
        f"{BASE_URL}/internal/study/events",
        headers={"X-INTERNAL-KEY": INTERNAL_KEY},
        json=payload,
        timeout=TIMEOUT
    )
    return res.status_code, res.text


def main():
    with open(INPUT_FILE, "r", encoding="utf-8-sig") as f:
        data = json.load(f)

    results = data.get("results", [])
    if not results:
        print("No results found in input file.")
        return

    state_counter = Counter()
    reason_counter = Counter()
    event_counter = Counter()

    success_count = 0
    fail_count = 0

    with requests.Session() as session:
        for idx, r in enumerate(results, start=1):
            judgment = r.get("judgment", {}) or {}

            state = judgment.get("state", "UNKNOWN")
            reason_code = judgment.get("reason_code", "NO_REASON")

            event_type = map_state_to_event(state)
            base_weight = map_state_to_weight(state)
            extra_weight = get_extra_weight(reason_code)
            weight = base_weight + extra_weight

            state_counter[state] += 1
            reason_counter[reason_code] += 1

            print(
                f"[{idx}] state={state} reason={reason_code} "
                f"-> event={event_type} x{weight} "
                f"(base={base_weight}, extra={extra_weight})"
            )

            for n in range(weight):
                try:
                    status_code, body = post_event(session, USER_ID, event_type)

                    if 200 <= status_code < 300:
                        success_count += 1
                        event_counter[event_type] += 1
                        print(f"    [{n+1}/{weight}] OK {event_type} -> {status_code}")
                    else:
                        fail_count += 1
                        print(f"    [{n+1}/{weight}] FAIL {event_type} -> {status_code} / {body}")

                except requests.RequestException as e:
                    fail_count += 1
                    print(f"    [{n+1}/{weight}] ERROR {event_type} -> {e}")

            if state == "MULTI_REPETITIVE_SIGNAL":
                done_event = "WRONG_REVIEW_DONE"
                try:
                    done_status, done_body = post_event(session, USER_ID, done_event)

                    if 200 <= done_status < 300:
                        success_count += 1
                        event_counter[done_event] += 1
                        print(f"    [DONE] OK {done_event} -> {done_status}")
                    else:
                        fail_count += 1
                        print(f"    [DONE] FAIL {done_event} -> {done_status} / {done_body}")

                except requests.RequestException as e:
                    fail_count += 1
                    print(f"    [DONE] ERROR {done_event} -> {e}")

    print("\n===== SUMMARY =====")
    print("State counts:")
    for state, cnt in state_counter.items():
        print(f"  {state}: {cnt}")

    print("\nReason counts:")
    for reason, cnt in reason_counter.items():
        print(f"  {reason}: {cnt}")

    print("\nInserted event counts:")
    for event_type, cnt in event_counter.items():
        print(f"  {event_type}: {cnt}")

    print(f"\nSuccess: {success_count}")
    print(f"Fail   : {fail_count}")


if __name__ == "__main__":
    main()