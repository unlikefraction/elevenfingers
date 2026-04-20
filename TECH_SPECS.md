# ElevenFingers — Technical Specification

**Version:** 1.0
**Platform:** iPadOS 17.0+
**Status:** Implementation-ready
**Audience:** Engineering team
**Distribution:** Personal / single-user, sideloaded via paid Apple Developer account

---

## 1. Product Overview

ElevenFingers is a floating keyboard replacement for iPadOS that combines Apple Pencil handwriting, voice recording, and a personalized writing style ruleset to produce typed text. The target use case is a user who finds on-screen typing slow and system dictation unreliable, and who wants their handwritten/spoken fragments rewritten into clean text in their own voice.

The user's input modes are:
- Handwriting on a canvas with Apple Pencil Pro
- Voice recording via the device microphone
- Both, combined into a single submission

When the user submits, the system runs OCR on the canvas image, STT on the audio, and then a "writer" model that merges both signals against the user's personal dictionary/ruleset to produce the final typed output.

---

## 2. Platform Constraints & Architectural Rationale

iPadOS keyboard extensions cannot access the microphone under any circumstance. This is a hard sandbox restriction enforced by the OS and is unaffected by `RequestsOpenAccess`. Keyboard extensions additionally operate under a ~60 MB jetsam memory ceiling, which PencilKit drawings can exhaust.

To deliver the required feature set, ElevenFingers uses a **hybrid architecture**: a fully-privileged iPad app runs in the background with an active audio session, and a keyboard extension hosts the user-facing UI. The two processes communicate through a shared App Group container and Darwin notifications. The keyboard performs no audio I/O and no network I/O; it is a presentation and IPC surface. All heavy work (mic, network, Gemini, ElevenLabs) happens in the main app.

This mirrors the pattern used successfully by Wispr Flow on iOS.

---

## 3. System Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                          iPad                                  │
│                                                                │
│  ┌──────────────────────┐        ┌──────────────────────────┐ │
│  │  Keyboard Extension  │        │     Main App (bg audio)  │ │
│  │                      │        │                          │ │
│  │  • PKCanvasView      │◄──────►│  • AVAudioRecorder       │ │
│  │  • Waveform view     │ Darwin │  • AVAudioEngine (levels)│ │
│  │  • Tool strip        │ notifs │  • Dictionary store      │ │
│  │  • Submit button     │   +    │  • Network pipeline      │ │
│  │  • System kbd toggle │ shared │  • Flow Session timer    │ │
│  │                      │  files │                          │ │
│  └──────────────────────┘        └─────────────┬────────────┘ │
│                                                 │              │
└─────────────────────────────────────────────────┼──────────────┘
                                                  │ HTTPS
                                                  │
                                ┌─────────────────▼──────────────┐
                                │     FastAPI Backend            │
                                │                                │
                                │  /ocr    → Gemini 3.1 Flash    │
                                │  /stt    → ElevenLabs Scribe v2│
                                │  /writer → Gemini 3.1 Flash    │
                                │                                │
                                │  3-day rolling log             │
                                └────────────────────────────────┘
```

### 3.1 Xcode Project Structure

Single Xcode workspace with three targets plus a shared framework:

```
ElevenFingers.xcworkspace
├── ElevenFingersApp/              # Main app target
│   ├── App/
│   │   ├── ElevenFingersApp.swift
│   │   └── ContentView.swift
│   ├── Audio/
│   │   ├── FlowSessionController.swift
│   │   ├── AudioRecorder.swift
│   │   └── LevelMeterTap.swift
│   ├── Network/
│   │   ├── BackendClient.swift
│   │   └── PipelineCoordinator.swift
│   ├── UI/
│   │   ├── DictionaryEditorView.swift
│   │   ├── OnboardingView.swift
│   │   └── DebugLogView.swift
│   ├── IPC/
│   │   └── KeyboardBridge.swift
│   ├── Resources/
│   │   └── Info.plist
│   └── ElevenFingersApp.entitlements
├── ElevenFingersKeyboard/         # Keyboard extension target
│   ├── KeyboardViewController.swift
│   ├── Canvas/
│   │   ├── CanvasHostView.swift
│   │   └── ToolStripView.swift
│   ├── Waveform/
│   │   └── WaveformView.swift
│   ├── Controls/
│   │   ├── BottomBarView.swift
│   │   └── SpacebarSliderView.swift
│   ├── IPC/
│   │   └── AppBridge.swift
│   ├── Resources/
│   │   └── Info.plist
│   └── ElevenFingersKeyboard.entitlements
├── ElevenFingersCore/             # Shared framework (both targets link)
│   ├── AppGroup.swift
│   ├── DarwinEvents.swift
│   ├── SharedPaths.swift
│   ├── DictionaryStore.swift
│   └── PipelineTypes.swift
└── Backend/                       # Python FastAPI service
    ├── main.py
    ├── ocr.py
    ├── stt.py
    ├── writer.py
    ├── prompts.py
    ├── env.py
    └── requirements.txt
```

App Group identifier: `group.com.elevenfingers.shared` (update to team prefix).
Bundle IDs: `com.elevenfingers.app` and `com.elevenfingers.app.keyboard`.

---

## 4. Main App Specification

### 4.1 Responsibilities
1. Acquire and hold the microphone permission.
2. Manage Flow Sessions (windowed periods during which the main app stays resident in the background with an active `AVAudioSession`).
3. Record audio to disk during recording events and stream audio levels to the keyboard.
4. Run the submission pipeline (canvas → `/ocr`, audio → `/stt`, both + dictionary → `/writer`).
5. Store and expose the user's personal dictionary.
6. Provide a foreground UI for onboarding, dictionary editing, session control, and debug inspection.

### 4.2 Tech Stack
- Swift 5.9+, SwiftUI for the main app UI
- `AVFoundation` for audio
- `URLSession` for network
- `UserDefaults` (app-group-scoped) for lightweight state; file container for binary blobs

### 4.3 Key Modules

**`FlowSessionController`** — singleton managing the session lifecycle.
- `start()` — activate `AVAudioSession` with category `.playAndRecord`, mode `.measurement`, options `[.duckOthers, .defaultToSpeaker]`. Begin background-task keep-alive. Schedule session expiry.
- `stop()` — deactivate session, post `ef.session.expired`.
- Session duration configurable: 5 min, 15 min, 1 hr, until-explicit-stop (persisted in user defaults).
- Listens for `ef.session.start` Darwin notification.

**`AudioRecorder`** — wraps `AVAudioRecorder` writing AAC to `shared/current.m4a`. Starts/stops in response to `ef.recording.start` / `ef.recording.stop`. Sample rate 16 kHz mono (adequate for Scribe v2 and keeps file size low).

**`LevelMeterTap`** — `AVAudioEngine` input-node tap computing RMS at ~20 Hz. Writes a 64-slot rolling float buffer to `shared/levels.bin` as a memory-mapped file. Posts `ef.levels.tick` after each update (throttled).

**`PipelineCoordinator`** — runs submission.
1. Reads `shared/canvas.png` and `shared/current.m4a` from container (either may be absent).
2. Reads the dictionary from `UserDefaults(suiteName: groupID)`.
3. Fires `/ocr` and `/stt` in parallel via `async let`.
4. On both completing (or empty results), fires `/writer`.
5. Writes the final string to `shared/result.txt`.
6. Posts `ef.result.ready`.
7. Emits structured log events via `Logger` (subsystem `com.elevenfingers.app`, category `pipeline`).

**`BackendClient`** — thin URLSession wrapper. Base URL read from `UserDefaults`. Configurable via debug UI (useful for local dev vs. Tailscale vs. tunnel). Timeouts: 15 s for `/ocr`, 30 s for `/stt`, 15 s for `/writer`. Retries once on network error, never on 4xx.

**`DictionaryStore`** — in shared framework. Stores a single string in `UserDefaults(suiteName:)`. Exposed as `@Published` in main app, read-only `get()` in keyboard.

### 4.4 Background Mode
- `UIBackgroundModes` includes `audio`.
- `AVAudioSession` must be active whenever a Flow Session is running; iOS will otherwise suspend the process.
- When the session expires, the app releases the audio session and may be suspended by iOS. The next `ef.session.start` from the keyboard requires the user to foreground the main app momentarily — this is expected and documented in user-facing copy as "tap to re-arm."

### 4.5 Foreground UI
Minimal. Four screens:
1. **Home** — current Flow Session state (active / expires-in / inactive), start/stop button, last result preview, "open keyboard settings" shortcut.
2. **Dictionary** — full-screen `TextEditor` bound to `DictionaryStore`, plus example/help text.
3. **Settings** — backend URL, session duration, language code for Scribe, clear-logs, sign-out-of-session.
4. **Debug** — live tail of pipeline logs; useful during development, hide in release.

### 4.6 Entitlements
```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.elevenfingers.shared</string>
</array>
```

### 4.7 `Info.plist` keys
- `NSMicrophoneUsageDescription` — "ElevenFingers records your voice and combines it with your handwriting to produce final text. Audio is sent to your configured backend and not retained on-device after submission."
- `UIBackgroundModes` — `["audio"]`
- `ITSAppUsesNonExemptEncryption` — `false`

---

## 5. Keyboard Extension Specification

### 5.1 Responsibilities
1. Render the floating keyboard UI (canvas, waveform, controls).
2. Capture Pencil input and maintain drawing state.
3. Signal the main app for session start, recording start/stop, submission.
4. Display waveform from shared level buffer.
5. Insert the final text via `UITextDocumentProxy`.
6. Provide a text-edit mode (caret slider on spacebar + globe to system keyboard).
7. Expose copy-canvas-as-image (local to extension, uses `UIPasteboard` directly).

### 5.2 Tech Stack
- UIKit (SwiftUI inside keyboard extensions has been unreliable for complex views; UIKit is safer for this target).
- `PencilKit` for canvas.
- `UIPencilInteraction` for Pencil Pro interactions.
- No third-party dependencies; keep binary small.

### 5.3 UI Layout

Floating keyboard, approximately 620×360 pt, mimicking Apple's pinched-in system keyboard visual style. Light mode only for v1.

```
┌──────────────────────────────────────────────────────┐
│  [●Rec]  ╭──── waveform ─────╮    [🗑 audio]        │ ← 44 pt top bar
├──────────────────────────────────────────────────────┤
│                                                      │
│                                                      │
│                  PKCanvasView                        │ ← ~240 pt canvas
│                                                      │
│                                                      │
├──────────────────────────────────────────────────────┤
│  [✎][⌫][∙]    [↶][↷]    [⎘ img][⌧ clear]  [submit]  │ ← 44 pt bottom bar
│   pen eraser                                          │
│   laser                                               │
├──────────────────────────────────────────────────────┤
│  [⌨ close]   [Aa text mode]   [🌐 system kbd]        │ ← 36 pt footer
└──────────────────────────────────────────────────────┘
```

Tool strip: pen / eraser / laser. Pencil Pro squeeze cycles through tools; double-tap toggles between pen and eraser. Tools implemented as:
- Pen → `PKInkingTool(.pen, color: .black, width: 2.5)`
- Eraser → `PKEraserTool(.vector)`
- Laser → custom overlay view that draws a fading red dot at touch points; does **not** mutate `PKDrawing`. Disappears after 600 ms with easing.

### 5.4 Memory Discipline
- Cap `PKCanvasView` bounds at 600×240 pt (logical).
- Use `drawingPolicy = .pencilOnly` to avoid finger-drawing overhead.
- Limit undo depth to 20 by maintaining a manual ring buffer of `PKDrawing` snapshots; disable the default `UndoManager` coalescing.
- On "clear canvas": set `canvasView.drawing = PKDrawing()`, then release and recreate the `PKCanvasView` if the process has been alive > 5 min.
- On "submit": render image, write to container, then immediately clear the drawing.
- Never load SwiftUI view hierarchies. Never link Combine in this target.

### 5.5 Waveform View
`UIView` subclass with a `CADisplayLink` running at 30 fps while `ef.levels.tick` subscription is active. Reads `shared/levels.bin` (memory-mapped). Draws 40 bars using `UIBezierPath` in the tint color. No gradient, no shadow.

### 5.6 Spacebar Caret Slider (Text Mode)
Text mode replaces the canvas area with a neutral surface showing the spacebar centered. `UIPanGestureRecognizer` on the spacebar view:
- On `.changed`: compute `delta = translation.x / pxPerChar` where `pxPerChar ≈ 10`. Call `textDocumentProxy.adjustTextPosition(byCharacterOffset: Int(delta))` and reset translation.
- On `.ended`: do nothing.
Also present a basic character delete key in this mode. No QWERTY is implemented; the globe button hands off to the system keyboard for full text editing.

### 5.7 Submit Flow (extension-side)
1. User taps submit.
2. If canvas has strokes: render to PNG (`drawing.image(from: bounds, scale: 2.0)`), write to `shared/canvas.png`. Otherwise write nothing.
3. Post `ef.submit`.
4. Show inline spinner in the bottom bar.
5. Start 30 s timeout.
6. On `ef.result.ready`: read `shared/result.txt`, call `textDocumentProxy.insertText(result)`, clear local canvas, clear local audio UI state.
7. On timeout: show an error toast with "Open app" CTA that triggers a URL scheme open (`elevenfingers://wake`).

### 5.8 Entitlements
```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.elevenfingers.shared</string>
</array>
```

### 5.9 `Info.plist` keys
- `NSExtension.NSExtensionAttributes.RequestsOpenAccess` = `YES` (required for App Group access)
- `NSExtension.NSExtensionAttributes.PrimaryLanguage` = `en-US`
- `NSExtension.NSExtensionAttributes.PrefersRightToLeft` = `false`
- `NSExtension.NSExtensionAttributes.IsASCIICapable` = `true`
- `NSExtension.NSExtensionPointIdentifier` = `com.apple.keyboard-service`
- `NSExtension.NSExtensionPrincipalClass` = `$(PRODUCT_MODULE_NAME).KeyboardViewController`

---

## 6. Inter-Process Communication Contract

### 6.1 Shared Container Layout

Mounted at `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.elevenfingers.shared")`.

| Path | Writer | Reader | Format | Purpose |
|---|---|---|---|---|
| `shared/current.m4a` | Main app | Main app | AAC audio | Active recording, overwritten each session |
| `shared/canvas.png` | Keyboard | Main app | PNG @2x | Canvas snapshot at submit time |
| `shared/result.txt` | Main app | Keyboard | UTF-8 text | Final pipeline output |
| `shared/levels.bin` | Main app | Keyboard | 64×Float32 little-endian | Rolling audio level buffer |
| `shared/session.json` | Main app | Keyboard | JSON | Session state (see below) |

`session.json` schema:
```json
{
  "active": true,
  "startedAt": 1745000000,
  "expiresAt": 1745003600,
  "recording": false,
  "lastResultAt": 1745002000
}
```

Dictionary is stored in `UserDefaults(suiteName: "group.com.elevenfingers.shared")` under key `dictionary` (single String, up to 8 KB). KVO-observed by both processes.

### 6.2 Darwin Notification Contract

Use `CFNotificationCenterGetDarwinNotifyCenter()` with no userInfo payload (Darwin notifications do not support userInfo across processes; all payloads must travel via shared container).

| Name | Posted by | Handler | Trigger |
|---|---|---|---|
| `com.elevenfingers.session.start` | Keyboard | Main app | User tapped "Start Flow" when no session active |
| `com.elevenfingers.session.stop` | Keyboard or Main | Both | Explicit stop |
| `com.elevenfingers.session.expired` | Main app | Keyboard | Session timer fired |
| `com.elevenfingers.recording.start` | Keyboard | Main app | Record button tapped |
| `com.elevenfingers.recording.stop` | Keyboard | Main app | Stop button or deletion |
| `com.elevenfingers.levels.tick` | Main app | Keyboard | Level buffer updated (throttled to ~20 Hz) |
| `com.elevenfingers.submit` | Keyboard | Main app | User tapped submit |
| `com.elevenfingers.result.ready` | Main app | Keyboard | Pipeline completed |
| `com.elevenfingers.result.failed` | Main app | Keyboard | Pipeline failed (see `shared/error.json`) |

Both processes instantiate an `IPCBridge` (one per target — `AppBridge` in keyboard, `KeyboardBridge` in app) which registers observers on init and provides `post(_:)` and handler closures.

### 6.3 Fallback When Main App Is Suspended

Darwin notifications do not wake a suspended process. The flow for `com.elevenfingers.submit` when the main app is cold:

1. Keyboard writes payload to container.
2. Keyboard posts `com.elevenfingers.submit`.
3. Keyboard starts a 400 ms wake-wait timer.
4. If no `com.elevenfingers.result.ready` or `com.elevenfingers.result.failed` arrives within the timeout and no Flow Session is active according to `shared/session.json`, keyboard transitions to a "needs wake" state showing a CTA.
5. CTA invokes `extensionContext?.open(URL(string: "elevenfingers://wake?pending=submit")!)` which launches the main app.
6. Main app processes the pending flag from the URL, runs the pipeline, returns foreground focus via `UIApplication.shared.open(URL(string: "previous-app-url-here")!)` — this step is best-effort; iOS does not guarantee return focus. Document as a known friction.

This matches Wispr Flow's "bounce back" UX.

---

## 7. Backend API Specification

Base URL configurable per-deploy. Authentication: none in v1 (personal use, exposed only via Tailscale or authenticated tunnel). Add bearer token for any non-private deployment.

### 7.1 `POST /ocr`

Run OCR on a handwriting image.

**Request** (multipart/form-data):
| Field | Type | Required | Notes |
|---|---|---|---|
| `image` | file (png/jpeg) | yes | Canvas snapshot, ≤ 4 MB |
| `dictionary` | string | no | User's ruleset; appended to system prompt |

**Response** (200, application/json):
```json
{ "text": "string", "elapsed_ms": 712 }
```

**Errors:**
- `400` malformed input
- `413` image too large
- `502` upstream Gemini error (retry-safe)
- `504` upstream timeout

**Prompt** (system instruction to Gemini):
> you will be given a handwritten note and a dictionary of a user. your job is to do a very good and semantic OCR. make sure to understand what the user wanted to convey and to write it in that style.

The user-turn content is the image part followed by a text part containing the dictionary if present. `thinking_level: MINIMAL`, `model: gemini-3.1-flash-lite-preview`.

### 7.2 `POST /stt`

Transcribe recorded audio.

**Request** (multipart/form-data):
| Field | Type | Required | Notes |
|---|---|---|---|
| `audio` | file (m4a/mp3/wav) | yes | ≤ 20 MB |
| `language_code` | string | no | ISO 639-3 (e.g. `eng`); default `eng` |

**Response** (200):
```json
{
  "text": "string",
  "language": "eng",
  "diarization": [ { "speaker": "spk_0", "start": 0.0, "end": 2.3, "text": "..." } ],
  "elapsed_ms": 1340
}
```

**Implementation:** Load bytes into `BytesIO`, call `elevenlabs.speech_to_text.convert(file=..., model_id="scribe_v2", tag_audio_events=True, language_code=..., diarize=True)`.

**Errors:** `400`, `413`, `502`, `504` as above.

### 7.3 `POST /writer`

Combine OCR + STT + dictionary into final typed output.

**Request** (application/json):
```json
{
  "ocr": "string | null",
  "stt": "string | null",
  "dictionary": "string | null"
}
```

**Response** (200):
```json
{ "text": "string", "elapsed_ms": 520 }
```

**Prompt** (system instruction to Gemini):
> you are a part of a keyboard.
>
> you will be given the OCR and STT from the user. this is what was understood by the system. you will also be given a dictionary / ruleset of how the user usually writes.
>
> your job is to output exactly what should be typed.

User-turn content is formatted exactly as:
```
OCR:
{ocr}

STT:
{stt}

Dictionary / Ruleset:
{dictionary}
```

Missing fields are replaced with the literal string `(none)`. Include the one-shot example from the provided code sample as a prior turn in the `contents` array — it substantially improves output quality and must not be removed.

Model: `gemini-3.1-flash-lite-preview`, `thinking_level: MINIMAL`, streaming.

### 7.4 Logging

- `logging.handlers.TimedRotatingFileHandler('app.log', when='D', backupCount=3, utc=True)`
- Log fields: timestamp, request_id (ULID), endpoint, duration_ms, status, bytes_in, bytes_out, upstream_latency_ms, error_class if any.
- Never log request bodies or final text. Log only sizes and durations.

### 7.5 Dependencies

`requirements.txt`:
```
fastapi>=0.110
uvicorn[standard]>=0.29
python-multipart>=0.0.9
google-genai>=0.3
elevenlabs>=0.30
python-dotenv>=1.0
```

Run: `uvicorn main:app --host 0.0.0.0 --port 8787`.

### 7.6 Deployment

Recommend: small VM (Hetzner, Fly.io) behind Cloudflare tunnel **OR** a Mac mini on Tailscale. Do not expose publicly in v1 — there is no auth. If public exposure is needed later, add a long bearer token in a middleware, rejected before any logging.

---

## 8. User Flows

### 8.1 First-Time Setup
1. User installs signed build via TestFlight or sideload.
2. Opens main app, is walked through:
   - Microphone permission prompt
   - Keyboard enablement (deep-link to Settings → General → Keyboard → Keyboards → Add → ElevenFingers → enable Full Access)
   - Dictionary seed (empty textbox with example text)
   - Backend URL configuration
3. App confirms health by `GET /health` and displays green state.

### 8.2 Normal Submission (Happy Path, Session Active)
1. User focuses a text field in any app; keyboard appears.
2. User taps record, speaks, taps stop.
3. User sketches clarifying notes on canvas.
4. User taps submit.
5. Spinner in bottom bar for ~1.5–3 s.
6. Text inserted at cursor. Canvas and audio state cleared.

### 8.3 Submission With Cold Main App
1. As above, user taps submit.
2. After 400 ms with no result, keyboard shows "ElevenFingers is asleep — tap to wake."
3. Tap opens main app via URL scheme; app wakes, runs pipeline, writes result.
4. User returns to prior app manually; reopens keyboard; keyboard detects `shared/result.txt` and prompts "Insert last result?" with Insert / Discard buttons.

### 8.4 Editing Previously Typed Text
1. User taps "Aa" text mode button in keyboard footer.
2. Canvas collapses; spacebar appears with slider affordance.
3. User pans horizontally on spacebar to move caret.
4. User taps globe to hand off to system keyboard for full character input.
5. User can return via iOS's keyboard switcher.

### 8.5 Dictionary Update
1. User opens main app → Dictionary tab.
2. Edits text, taps Save.
3. `DictionaryStore` writes to shared `UserDefaults`; change visible immediately in keyboard and in all three backend endpoints on next call.

---

## 9. Permissions, Entitlements, Provisioning

| Capability | Main App | Keyboard | Notes |
|---|---|---|---|
| App Groups | ✓ | ✓ | Same group ID on both targets |
| Microphone | ✓ | — | Requested at first onboarding step |
| Background Modes → Audio | ✓ | — | Required to hold Flow Session |
| Network | ✓ | — | Keyboard performs no network I/O |
| RequestsOpenAccess | — | ✓ | User must enable Full Access |

Provisioning:
- Paid Apple Developer account ($99/yr). Free accounts give 7-day provisioning which is untenable.
- Developer Mode enabled on the target iPad.
- Install via Xcode direct-to-device, TestFlight internal testing, or Apple Configurator for sideload.
- App Store distribution is **out of scope for v1** and would require auth, privacy policy, and likely a rework of the Flow Session UX to pass review.

---

## 10. Third-Party Services

| Service | Purpose | SDK | Key location |
|---|---|---|---|
| Google Gemini (`gemini-3.1-flash-lite-preview`) | OCR + Writer | `google-genai` Python SDK | `Backend/env.py` → `GEMINI_API_KEY` |
| ElevenLabs Scribe v2 | STT | `elevenlabs` Python SDK | `Backend/env.py` → `ELEVENLABS_API_KEY` |

No third-party SDKs are linked into the iOS binaries. All API keys live server-side only.

---

## 11. Risks & Known Limitations

1. **Cold-start bounce UX** (Section 6.3) — unavoidable without a jailbreak; must be communicated clearly in-product.
2. **Memory pressure in keyboard** — mitigations in 5.4. Test with 10-min continuous-use sessions.
3. **Background audio revocation** — iOS will occasionally revoke background audio when the device is under pressure or the user force-quits the main app. Detect via `AVAudioSession.interruptionNotification` and surface "session lost — tap to re-arm."
4. **Network dependency** — the pipeline requires the backend to be reachable. No on-device fallback in v1. Consider caching the last dictionary and last result for display during offline state.
5. **Pencil Pro features on non-Pro Pencils** — squeeze is silently ignored on Pencil 2; ensure tool-strip tap remains the primary mechanism.
6. **Keyboard extension cannot access the clipboard from the host app's private text views** — some banking/secure fields will disable custom keyboards entirely. Expected and not mitigatable.
7. **Sideload signing expiry** — paid dev account provisioning lasts 1 year; set a calendar reminder.

---

## 12. Implementation Phases

### Phase 0 — Scaffolding (1–2 days)
- Xcode workspace with both targets and shared framework.
- App Group + entitlements wired up and verified with a round-trip file write.
- Darwin notification helper class in shared framework with a smoke test (app posts → keyboard observes).
- FastAPI skeleton with `/health` only.

### Phase 1 — Backend complete (2–3 days)
- `/ocr`, `/stt`, `/writer` implemented against exact prompts.
- Logging, error envelopes.
- Smoke-tested end-to-end from `curl`.

### Phase 2 — Keyboard UI shell (2–3 days)
- Floating-size UI with all buttons visually in place but stubbed.
- `PKCanvasView` with tools, undo/redo, clear, copy-as-image.
- Spacebar slider in text mode.
- No IPC yet.

### Phase 3 — Main app engine (3–4 days)
- Flow Session controller, audio recorder, level tap.
- Dictionary editor.
- Backend client and pipeline coordinator.
- Debug log view.

### Phase 4 — IPC wiring (2 days)
- All Darwin events and shared-file contracts connected end-to-end.
- Cold-start fallback via URL scheme.

### Phase 5 — Polish (2–3 days)
- Pencil Pro interactions tuned (squeeze, double-tap).
- Haptics on submit, record, clear.
- Light-mode visual pass against Apple's system keyboard.
- Error states and empty states.

### Phase 6 — Hardening (2 days)
- Memory stress test (10-min continuous session).
- Background audio interruption handling.
- Provisioning + install docs.

**Total estimate:** ~15–20 engineering days for one senior iOS engineer plus backend time in parallel.

---

## Appendix A — Exact Prompts

These prompts are authoritative. Do not rewrite them during implementation; the pipeline has been tuned against these exact strings and is described as "extremely robust to errors and misreading."

**OCR system instruction:**
```
you will be given a handwritten note and a dictionary of a user. your job is to do a very good and semantic OCR. make sure to understand what the user wanted to convey and to write it in that style.
```

**Writer system instruction:**
```
you are a part of a keyboard.

you will be given the OCR and STT from the user. this is what was understood by the system. you will also be given a dictionary / ruleset of how the user usually writes.

your job is to output exactly what should be typed.
```

**Writer one-shot example** (must be included in `contents` before the actual user turn):

*User turn:*
```
OCR:
Dd you get someting? sket?

STT:
I Mean to Write Did You Get Something? Skate With a Laughing Emoji at the start and the END. oh, and write this in proper grammer. its important. make the first letter capital.

Dictionary / Ruleset:
Name: Saket
Place: Una
Rule: I write everything in lowercase
```

*Model turn:*
```
😂 Did you get something, Saket? 😂
```

---

## Appendix B — Reference Python Snippets

Use these as authoritative templates. Wrap in FastAPI endpoints per Section 7.

### Gemini call skeleton
```python
from google import genai
from google.genai import types

client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])

def gemini_call(system_instruction: str, contents: list, model="gemini-3.1-flash-lite-preview") -> str:
    config = types.GenerateContentConfig(
        thinking_config=types.ThinkingConfig(thinking_level="MINIMAL"),
        system_instruction=[types.Part.from_text(text=system_instruction)],
    )
    out = []
    for chunk in client.models.generate_content_stream(model=model, contents=contents, config=config):
        if chunk.text:
            out.append(chunk.text)
    return "".join(out)
```

### ElevenLabs Scribe call skeleton
```python
from elevenlabs.client import ElevenLabs
from io import BytesIO

elevenlabs = ElevenLabs(api_key=os.environ["ELEVENLABS_API_KEY"])

def transcribe(audio_bytes: bytes, language_code: str = "eng"):
    return elevenlabs.speech_to_text.convert(
        file=BytesIO(audio_bytes),
        model_id="scribe_v2",
        tag_audio_events=True,
        language_code=language_code,
        diarize=True,
    )
```

---

## Appendix C — Acceptance Criteria (v1)

The build is complete when:
1. A user can enable the keyboard and grant Full Access with no crashes.
2. With a Flow Session active, the user can record audio, draw on the canvas, and submit, and see the final text inserted into Notes, Mail, and Safari within 3 seconds on Wi-Fi.
3. Undo/redo works across ≥10 operations without memory warnings.
4. Clear canvas and delete-audio-with-confirmation both work.
5. The copy-canvas-as-image button places a PNG on the system pasteboard.
6. Spacebar slider moves the caret character-by-character in Notes.
7. Globe key switches to the Apple keyboard in one tap.
8. Dictionary edits in the main app affect the next submission's output.
9. Cold main app triggers the documented "tap to wake" flow and completes pipeline after wake.
10. The backend's 3-day log rotation works and contains no user content.