We are making ElevenFingers

this is a keyboard for ipad that is designed to be used with apple pencil and voice.
its a floating keyboard like the one that apple's own keyboard gets when pinched in.
the reason this exists is because writing to type a message is badly broken on ipados. and dictation is also limited.
we want to use both as our modalities combined with the state of the art tech to make the writing experience incredible.

so, it is basically a whiteboard + voice recorder
here is a feature list.
1. functioning whiteboard with first party support for apple pencil pro (squeeze for options, double tap for toggle between pen and eraser).
2. only 3 tools needed. pen, eraser and a laser.
3. a voice recorder (at the top of the beyboard. it records, shows waveform as it records and can be stopped and started again)
4. an option to copy the things in canvas as an image.
5. submit button is bottom right.
6. a close keyboard button on the bottom left.
7. an option to clear the canvas.
8. undo, redo for everything on the canvas.
9. delete recorded audio option with confirmation.

now, the flow that happens after submit:
if something was written on the canvas, it takes a photo of it. and then we'll do an ocr of it via gemini 3.1 flash lite.
then if something was recorded, then send that to elevenlabs scribe v2




this is how to do OCR:
# pip install google-genai
```python
import os
from google import genai
from google.genai import types


def generate():
    client = genai.Client(
        api_key=os.environ.get("GEMINI_API_KEY"),
    )

    model = "gemini-3.1-flash-lite-preview"
    contents = [
        types.Content(
            role="user",
            parts=[
                types.Part.from_text(text="""INSERT_INPUT_HERE"""),
            ],
        ),
    ]
    generate_content_config = types.GenerateContentConfig(
        thinking_config=types.ThinkingConfig(
            thinking_level="MINIMAL",
        ),
        system_instruction=[
            types.Part.from_text(text="""you will be given a handwritten note and a dictionary of a user. your job is to do a very good and semantic OCR. make sure to understand what the user wanted to convey and to write it in that style."""),
        ],
    )

    for chunk in client.models.generate_content_stream(
        model=model,
        contents=contents,
        config=generate_content_config,
    ):
        if text := chunk.text:
            print(text, end="")

if __name__ == "__main__":
    generate()

```



this is how to do STT:
ELEVENLABS_API_KEY=<your_api_key_here>

```python
pip install elevenlabs
pip install python-dotenv


# example.py
import os
from dotenv import load_dotenv
from io import BytesIO
import requests
from elevenlabs.client import ElevenLabs

load_dotenv()

elevenlabs = ElevenLabs(
  api_key=os.getenv("ELEVENLABS_API_KEY"),
)

audio_url = (
    "https://storage.googleapis.com/eleven-public-cdn/audio/marketing/nicole.mp3"
)
response = requests.get(audio_url)
audio_data = BytesIO(response.content)

transcription = elevenlabs.speech_to_text.convert(
    file=audio_data,
    model_id="scribe_v2", # Model to use
    tag_audio_events=True, # Tag audio events like laughter, applause, etc.
    language_code="eng", # Language of the audio file. If set to None, the model will detect the language automatically.
    diarize=True, # Whether to annotate who is speaking
)

print(transcription)
```


now, we'll have a fastapi backend to handle all the requests. rn open for all.
all the keys you'll need for making the backend is stored inside env.py
the backend's job is just minor orchastration and handling requests. wont really be many requests.
at max store a 3 days rolling log file. and you'll need to temporaily store the audio file that can then be used send the link to elevenlabs. if they dont support direct audio upload.



ok, now, the most important thing. we need to maintain a personal dictionary of the user.
for this in the keyboard there will be a disctionary option in which i can write words, rules, spellings, other things of how i like to do thing.

this is basically a text field that is a prompt that is appended to all three, OCR, stt and writer (i'll tell you what it is).

now, then someone enters that dictionary... we need a proper keyboard. use a library / gboard if possible. it'll start off empty.



now, this is what writer does.
it takes in what we get back from OCR and STT and combines it to write the final thing.



this is the code for writer: i've also included an exmaple. strip that in your code.
```python
# To run this code you need to install the following dependencies:
# pip install google-genai

import os
from google import genai
from google.genai import types


def generate():
    client = genai.Client(
        api_key=os.environ.get("GEMINI_API_KEY"),
    )

    model = "gemini-3.1-flash-lite-preview"
    contents = [
        types.Content(
            role="user",
            parts=[
                types.Part.from_text(text="""OCR:
Dd you get someting? sket?

STT:
I Mean to Write Did You Get Something? Skate With a Laughing Emoji at the start and the END. oh, and write this in proper grammer. its important. make the first letter capital.


Dictionary / Ruleset:
Name: Saket
Place: Una
Rule: I write everything in lowercase"""),
            ],
        ),
        types.Content(
            role="model",
            parts=[
                types.Part.from_text(text="""😂 Did you get something, Saket? 😂"""),
            ],
        ),
        types.Content(
            role="user",
            parts=[
                types.Part.from_text(text="""INSERT_INPUT_HERE"""),
            ],
        ),
    ]
    generate_content_config = types.GenerateContentConfig(
        thinking_config=types.ThinkingConfig(
            thinking_level="MINIMAL",
        ),
        system_instruction=[
            types.Part.from_text(text="""you are a part of a keyboard.

you will be given the OCR and STT from the user. this is what was understood by the system. you will also be given a dictionary / ruleset of how the user usually writes.

your job is to output exactly what should be typed."""),
        ],
    )

    for chunk in client.models.generate_content_stream(
        model=model,
        contents=contents,
        config=generate_content_config,
    ):
        if text := chunk.text:
            print(text, end="")

if __name__ == "__main__":
    generate()



# Actual model output
"😂 Did you get something, Saket? 😂"
```





use the same prompts.
the current system is extremely robust to errors and misreading.

and write it in native.
use all apple's components. everything in light mode and super pretty. apple UI.

lets make the best keyboard on ipad.



oh, and have an option to toggle to a normal keyboard in case the user wants to edit something they have written.
it should have one feature where sliding on the spacebar becomes a slider for the caret's position.
and give a one tap toggle to go back to apple keyboard.

this is only for me personally so we can get elevated access to the system to make it happen



Read ./TECH_SPECS.md for how to implement