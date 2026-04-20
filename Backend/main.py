import asyncio
import logging
import time
import uuid
from logging.handlers import TimedRotatingFileHandler
from pathlib import Path

from fastapi import FastAPI, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

import env  # noqa: F401 — sets env vars
from ocr import run_ocr
from stt import run_stt
from writer import run_writer

MAX_IMAGE_BYTES = 4 * 1024 * 1024
MAX_AUDIO_BYTES = 20 * 1024 * 1024

LOG_DIR = Path("/var/log/elevenfingers")
try:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    LOG_FILE = LOG_DIR / "app.log"
except PermissionError:
    LOG_FILE = Path("app.log")

logger = logging.getLogger("elevenfingers")
logger.setLevel(logging.INFO)
handler = TimedRotatingFileHandler(
    str(LOG_FILE), when="D", backupCount=3, utc=True
)
handler.setFormatter(
    logging.Formatter(
        '{"ts":"%(asctime)s","lvl":"%(levelname)s","msg":%(message)s}'
    )
)
logger.addHandler(handler)
logger.addHandler(logging.StreamHandler())


def log_event(event: dict) -> None:
    import json

    logger.info(json.dumps(event, separators=(",", ":"), ensure_ascii=False))


app = FastAPI(title="ElevenFingers Backend", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def attach_request_id(request: Request, call_next):
    request_id = str(uuid.uuid4())
    request.state.request_id = request_id
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    return response


@app.get("/health")
async def health():
    return {"ok": True, "service": "elevenfingers", "version": "1.0.0"}


class OCRResponse(BaseModel):
    text: str
    elapsed_ms: int


@app.post("/ocr", response_model=OCRResponse)
async def ocr_endpoint(
    request: Request,
    image: UploadFile,
    dictionary: str | None = Form(default=None),
):
    if image.content_type not in ("image/png", "image/jpeg", "image/jpg"):
        raise HTTPException(status_code=400, detail="image must be png or jpeg")

    data = await image.read()
    if len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="image too large")
    if not data:
        raise HTTPException(status_code=400, detail="image is empty")

    mime = image.content_type or "image/png"
    try:
        text, elapsed = await asyncio.to_thread(run_ocr, data, mime, dictionary)
    except Exception as exc:
        log_event({
            "id": request.state.request_id,
            "endpoint": "/ocr",
            "error": exc.__class__.__name__,
            "bytes_in": len(data),
        })
        raise HTTPException(status_code=502, detail=f"ocr upstream error: {exc}")

    log_event({
        "id": request.state.request_id,
        "endpoint": "/ocr",
        "status": 200,
        "bytes_in": len(data),
        "bytes_out": len(text.encode("utf-8")),
        "upstream_ms": elapsed,
    })
    return OCRResponse(text=text, elapsed_ms=elapsed)


class STTResponse(BaseModel):
    text: str
    language: str | None = None
    diarization: list[dict] = []
    elapsed_ms: int


@app.post("/stt", response_model=STTResponse)
async def stt_endpoint(
    request: Request,
    audio: UploadFile,
    language_code: str | None = Form(default="eng"),
):
    data = await audio.read()
    if len(data) > MAX_AUDIO_BYTES:
        raise HTTPException(status_code=413, detail="audio too large")
    if not data:
        raise HTTPException(status_code=400, detail="audio is empty")

    try:
        result, elapsed = await asyncio.to_thread(
            run_stt, data, language_code or "eng"
        )
    except Exception as exc:
        log_event({
            "id": request.state.request_id,
            "endpoint": "/stt",
            "error": exc.__class__.__name__,
            "bytes_in": len(data),
        })
        raise HTTPException(status_code=502, detail=f"stt upstream error: {exc}")

    log_event({
        "id": request.state.request_id,
        "endpoint": "/stt",
        "status": 200,
        "bytes_in": len(data),
        "bytes_out": len(result["text"].encode("utf-8")),
        "upstream_ms": elapsed,
    })
    return STTResponse(elapsed_ms=elapsed, **result)


class WriterRequest(BaseModel):
    ocr: str | None = None
    stt: str | None = None
    dictionary: str | None = None


class WriterResponse(BaseModel):
    text: str
    elapsed_ms: int


@app.post("/writer", response_model=WriterResponse)
async def writer_endpoint(request: Request, payload: WriterRequest):
    try:
        text, elapsed = await asyncio.to_thread(
            run_writer, payload.ocr, payload.stt, payload.dictionary
        )
    except Exception as exc:
        log_event({
            "id": request.state.request_id,
            "endpoint": "/writer",
            "error": exc.__class__.__name__,
        })
        raise HTTPException(status_code=502, detail=f"writer upstream error: {exc}")

    log_event({
        "id": request.state.request_id,
        "endpoint": "/writer",
        "status": 200,
        "bytes_out": len(text.encode("utf-8")),
        "upstream_ms": elapsed,
    })
    return WriterResponse(text=text, elapsed_ms=elapsed)


@app.get("/")
async def root():
    return {
        "service": "elevenfingers",
        "endpoints": ["/health", "/ocr", "/stt", "/writer"],
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8787, reload=False)
