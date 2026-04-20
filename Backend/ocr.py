import time

from google import genai
from google.genai import types

from env import GEMINI_API_KEY
from prompts import OCR_SYSTEM

_client: genai.Client | None = None
MODEL = "gemini-3.1-flash-lite-preview"


def _client_instance() -> genai.Client:
    global _client
    if _client is None:
        _client = genai.Client(api_key=GEMINI_API_KEY)
    return _client


def run_ocr(image_bytes: bytes, mime_type: str, dictionary: str | None) -> tuple[str, int]:
    client = _client_instance()

    image_part = types.Part.from_bytes(data=image_bytes, mime_type=mime_type)
    dict_text = (dictionary or "").strip() or "(none)"
    text_part = types.Part.from_text(
        text=f"Dictionary / Ruleset:\n{dict_text}"
    )

    contents = [
        types.Content(role="user", parts=[image_part, text_part]),
    ]
    config = types.GenerateContentConfig(
        thinking_config=types.ThinkingConfig(thinking_level="MINIMAL"),
        system_instruction=[types.Part.from_text(text=OCR_SYSTEM)],
    )

    start = time.perf_counter()
    chunks: list[str] = []
    for chunk in client.models.generate_content_stream(
        model=MODEL,
        contents=contents,
        config=config,
    ):
        if chunk.text:
            chunks.append(chunk.text)
    elapsed_ms = int((time.perf_counter() - start) * 1000)
    return "".join(chunks).strip(), elapsed_ms
