import time
from io import BytesIO

from elevenlabs.client import ElevenLabs

from env import ELEVENLABS_API_KEY

_client: ElevenLabs | None = None


def _client_instance() -> ElevenLabs:
    global _client
    if _client is None:
        _client = ElevenLabs(api_key=ELEVENLABS_API_KEY)
    return _client


def run_stt(audio_bytes: bytes, language_code: str = "eng") -> tuple[dict, int]:
    client = _client_instance()

    start = time.perf_counter()
    result = client.speech_to_text.convert(
        file=BytesIO(audio_bytes),
        model_id="scribe_v2",
        tag_audio_events=True,
        language_code=language_code or None,
        diarize=True,
    )
    elapsed_ms = int((time.perf_counter() - start) * 1000)

    text = getattr(result, "text", "") or ""
    language = getattr(result, "language_code", None) or language_code
    diarization: list[dict] = []
    words = getattr(result, "words", None) or []
    current_speaker: str | None = None
    current_start: float | None = None
    current_end: float | None = None
    current_text: list[str] = []

    for w in words:
        speaker = getattr(w, "speaker_id", None)
        wtype = getattr(w, "type", None)
        wstart = getattr(w, "start", None)
        wend = getattr(w, "end", None)
        wtext = getattr(w, "text", "") or ""
        if wtype != "word":
            if current_text:
                current_text.append(wtext)
            continue
        if speaker != current_speaker:
            if current_speaker is not None and current_text:
                diarization.append({
                    "speaker": current_speaker,
                    "start": current_start or 0.0,
                    "end": current_end or 0.0,
                    "text": "".join(current_text).strip(),
                })
            current_speaker = speaker
            current_start = wstart
            current_text = []
        current_text.append(wtext)
        current_end = wend

    if current_speaker is not None and current_text:
        diarization.append({
            "speaker": current_speaker,
            "start": current_start or 0.0,
            "end": current_end or 0.0,
            "text": "".join(current_text).strip(),
        })

    return (
        {
            "text": text,
            "language": language,
            "diarization": diarization,
        },
        elapsed_ms,
    )
