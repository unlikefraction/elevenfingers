import time

from google import genai
from google.genai import types

from env import GEMINI_API_KEY
from prompts import (
    WRITER_EXAMPLE_MODEL,
    WRITER_EXAMPLE_USER,
    WRITER_SYSTEM,
    writer_user_turn,
)

_client: genai.Client | None = None
MODEL = "gemini-3.1-flash-lite-preview"


def _client_instance() -> genai.Client:
    global _client
    if _client is None:
        _client = genai.Client(api_key=GEMINI_API_KEY)
    return _client


def run_writer(
    ocr: str | None,
    stt: str | None,
    dictionary: str | None,
) -> tuple[str, int]:
    client = _client_instance()

    contents = [
        types.Content(
            role="user",
            parts=[types.Part.from_text(text=WRITER_EXAMPLE_USER)],
        ),
        types.Content(
            role="model",
            parts=[types.Part.from_text(text=WRITER_EXAMPLE_MODEL)],
        ),
        types.Content(
            role="user",
            parts=[types.Part.from_text(text=writer_user_turn(ocr, stt, dictionary))],
        ),
    ]
    config = types.GenerateContentConfig(
        thinking_config=types.ThinkingConfig(thinking_level="MINIMAL"),
        system_instruction=[types.Part.from_text(text=WRITER_SYSTEM)],
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
