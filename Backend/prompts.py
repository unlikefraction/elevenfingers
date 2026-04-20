OCR_SYSTEM = (
    "you will be given a handwritten note and a dictionary of a user. "
    "your job is to do a very good and semantic OCR. make sure to "
    "understand what the user wanted to convey and to write it in that style."
)

WRITER_SYSTEM = (
    "you are a part of a keyboard.\n\n"
    "you will be given the OCR and STT from the user. this is what was "
    "understood by the system. you will also be given a dictionary / "
    "ruleset of how the user usually writes.\n\n"
    "your job is to output exactly what should be typed."
)

WRITER_EXAMPLE_USER = (
    "OCR:\n"
    "Dd you get someting? sket?\n\n"
    "STT:\n"
    "I Mean to Write Did You Get Something? Skate With a Laughing Emoji "
    "at the start and the END. oh, and write this in proper grammer. its "
    "important. make the first letter capital.\n\n\n"
    "Dictionary / Ruleset:\n"
    "Name: Saket\n"
    "Place: Una\n"
    "Rule: I write everything in lowercase"
)

WRITER_EXAMPLE_MODEL = "\U0001F602 Did you get something, Saket? \U0001F602"


def writer_user_turn(ocr: str | None, stt: str | None, dictionary: str | None) -> str:
    def fill(v: str | None) -> str:
        return v if v and v.strip() else "(none)"

    return (
        f"OCR:\n{fill(ocr)}\n\n"
        f"STT:\n{fill(stt)}\n\n"
        f"Dictionary / Ruleset:\n{fill(dictionary)}"
    )
