import os
from pathlib import Path

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).with_name(".env"))
except ImportError:
    pass


def _required(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(
            f"Missing {name}. Set it in Backend/.env or the process environment."
        )
    return value


GEMINI_API_KEY = _required("GEMINI_API_KEY")
ELEVENLABS_API_KEY = _required("ELEVENLABS_API_KEY")
