# ElevenFingers

A floating iPad keyboard that combines Apple Pencil handwriting, voice recording, and a personal writing ruleset to produce typed text.

## Layout

- `ElevenFingersApp/` — main app (SwiftUI, owns mic + network)
- `ElevenFingersKeyboard/` — keyboard extension (UIKit + PencilKit)
- `ElevenFingersCore/` — shared sources (App Group, Darwin events, dictionary)
- `Backend/` — FastAPI (OCR via Gemini 3.1 flash lite, STT via ElevenLabs Scribe v2, writer)
- `project.yml` — XcodeGen config (run `xcodegen generate` to (re)build the `.xcodeproj`)

## iOS build

```bash
brew install xcodegen
xcodegen generate
open ElevenFingers.xcodeproj
```

Set your **Development Team** on both targets in Signing & Capabilities, then change the app group identifier if Xcode asks.

## Backend

```bash
cd Backend
pip install -r requirements.txt
python main.py
```

Runs on `:8787`. Hosted copy: `https://elevenfingers.unlikefraction.com`.

## Tech spec

See `TECH_SPECS.md` for the full product + technical spec.
