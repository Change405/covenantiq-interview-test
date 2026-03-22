import argparse
import json
import os
import time
import uuid
from datetime import datetime, timezone


SERVICE_NAME = os.getenv("SERVICE_NAME", "worker")
APP_ENV = os.getenv("APP_ENV", "unknown")
QUEUE_DIR = os.getenv("QUEUE_DIR", "/queue")
MODE = os.getenv("WORKER_MODE", "consume")
POLL_SECONDS = float(os.getenv("POLL_SECONDS", "0.5"))


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def emit_log(event: str, **extra):
    payload = {
        "ts": utc_now_iso(),
        "level": "info",
        "service": SERVICE_NAME,
        "event": event,
        "env": APP_ENV,
    }
    payload.update(extra)
    print(json.dumps(payload), flush=True)


def ensure_dirs():
    os.makedirs(os.path.join(QUEUE_DIR, "messages"), exist_ok=True)
    os.makedirs(os.path.join(QUEUE_DIR, "processed"), exist_ok=True)


def enqueue_once():
    ensure_dirs()
    message_id = str(uuid.uuid4())
    created_at = utc_now_iso()

    msg = {
        "messageId": message_id,
        "createdAt": created_at,
        "service": SERVICE_NAME,
        "env": APP_ENV,
        "payload": {"text": "takehome"},
    }

    filename = f"msg-{message_id}.json"
    path = os.path.join(QUEUE_DIR, "messages", filename)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(msg, f)

    emit_log("queue_enqueued", messageId=message_id)
    return 0


def consume_forever():
    ensure_dirs()
    emit_log("startup", queueDir=QUEUE_DIR)

    while True:
        messages_dir = os.path.join(QUEUE_DIR, "messages")
        processed_dir = os.path.join(QUEUE_DIR, "processed")

        files = sorted(
            f for f in os.listdir(messages_dir) if f.startswith("msg-") and f.endswith(".json")
        )

        if not files:
            time.sleep(POLL_SECONDS)
            continue

        file_name = files[0]
        msg_path = os.path.join(messages_dir, file_name)
        try:
            with open(msg_path, "r", encoding="utf-8") as f:
                msg = json.load(f)
        except Exception as e:
            emit_log("queue_message_read_failed", error=str(e), file=file_name)
            time.sleep(POLL_SECONDS)
            continue

        message_id = msg.get("messageId", file_name)
        emit_log("queue_dequeued", messageId=message_id)

        # Deterministic processing: we just move the message to processed.
        processed_name = f"processed-{message_id}.json"
        processed_path = os.path.join(processed_dir, processed_name)
        try:
            with open(processed_path, "w", encoding="utf-8") as f:
                json.dump({"processedAt": utc_now_iso(), "message": msg}, f)

            os.remove(msg_path)
        except Exception as e:
            emit_log("queue_processing_failed", messageId=message_id, error=str(e))
            time.sleep(POLL_SECONDS)
            continue

        emit_log("queue_processed", messageId=message_id)
        # Tiny sleep to avoid tight loops if files are huge.
        time.sleep(0.1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", default=None, choices=["consume", "enqueue_once"])
    args = parser.parse_args()

    mode = args.mode or MODE
    if mode == "enqueue_once":
        raise SystemExit(enqueue_once())

    consume_forever()


if __name__ == "__main__":
    main()

