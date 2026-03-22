from fastapi import FastAPI, Request
import json
import os
import uuid
from datetime import datetime, timezone

app = FastAPI()

SERVICE_NAME = os.getenv("SERVICE_NAME", "service-b")
APP_ENV = os.getenv("APP_ENV", "unknown")


@app.middleware("http")
async def request_id_middleware(request: Request, call_next):
    request_id = request.headers.get("x-request-id") or str(uuid.uuid4())
    request.state.request_id = request_id
    response = await call_next(request)
    response.headers["x-request-id"] = request_id
    return response


def emit_log(event: str, request: Request | None = None):
    payload = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "level": "info",
        "service": SERVICE_NAME,
        "event": event,
        "env": APP_ENV,
        "requestId": getattr(request.state, "request_id", None) if request else None,
    }
    print(json.dumps(payload), flush=True)


@app.get("/healthz")
async def healthz(request: Request):
    emit_log("healthz_ok", request=request)
    return {"status": "ok", "service": SERVICE_NAME}


@app.get("/")
async def root():
    return {"status": "ok"}


emit_log("startup", request=None)

