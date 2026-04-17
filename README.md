# PromptGlass

<img src="icon.png" alt="PromptGlass icon" width="128">

A native macOS teleprompter application that tracks your speech in real time, highlights the word you are currently saying, and scrolls the script to keep your reading position comfortably in view.

## What it does

PromptGlass is built for narrators, presenters, and content creators who read from a prepared script. You write or paste your script, start a session, and speak into your microphone. The app listens continuously and advances a highlight through the text word by word as you speak, so you always know exactly where you are in the script without losing your place.

Key capabilities:

- **Live word highlighting** — the current spoken word is highlighted and visually distinct from past and upcoming words.
- **Auto-scroll** — the teleprompter window scrolls automatically so the current word sits near the upper third of the visible area, keeping the most upcoming text in view below it.
- **Stage direction support** — wrap any text in square brackets to mark it as a direction note (e.g. `[pause]`, `[look to camera 2]`). Direction text is displayed in a visually distinct style and is excluded from speech matching entirely.
- **Scan-forward recovery** — if the speech recognizer misses a word, mispronounces something, or you skip ahead in the script, the alignment engine scans forward through the upcoming text and locks onto the best matching position. The app does not stall when recognition drifts.
- **Audio recording** — narration is recorded to a timestamped `.m4a` file in the app's support directory for every session.
- **Elapsed timer** — a session clock is visible during prompting.
- **Live audio meter** — a waveform-style visualization confirms microphone input is active.
- ** AI Assistant ** -- allows you to specify an OpenAI (local or Cloud based) model that then can be used to write or assist with script creation

## Requirements

- macOS 14 or later
- Microphone access
- Speech Recognition access (Apple on-device)

## Building

Open `PromptGlass.xcodeproj` in Xcode and build, or use the command line:

```bash
xcodebuild -project PromptGlass.xcodeproj -scheme PromptGlass -configuration Debug build
```

Run all tests:

```bash
xcodebuild test -project PromptGlass.xcodeproj -scheme PromptGlass -destination 'platform=macOS'
```

## Architecture overview

The app is structured as SwiftUI-first with explicit AppKit interop where SwiftUI alone is insufficient — specifically for per-word text layout geometry and scroll control in the teleprompter view.

| Layer | Responsibility |
|---|---|
| `Views/` | SwiftUI views; no business logic |
| `ViewModels/` | Observable state; bridge between services and views |
| `Services/` | All non-UI logic; independently testable |
| `Models/` | Plain data types |
| `Utilities/` | Stateless helpers (text normalization, fuzzy matching, time formatting) |

The central service is `SpeechAlignmentEngine`, which maintains a cursor into the script's spoken tokens, accepts partial `SFSpeechRecognitionResult` updates, and advances using a scoring model that combines exact matches, fuzzy edit-distance similarity, consecutive-match streak bonuses, and a penalty for large forward jumps. It never moves backward.

The audio pipeline uses a single `AVAudioEngine` tap shared by speech recognition, the audio level meter, and the file recorder — so the microphone is opened only once.

Speech recognition is wrapped behind a `SpeechRecognizing` protocol so the underlying engine can be replaced without changing calling code.

## Permissions

On first launch the app requests microphone and speech recognition access with usage descriptions explaining why each is needed. If either permission is denied, the app provides guidance for enabling it in System Settings and degrades gracefully rather than crashing.

## Script format

Scripts are plain text. Two types of bracket tags are supported:

**Stage directions** — `[pause]`, `[look to camera 2]`  
Displayed in the teleprompter in a faded italic style. Excluded from speech alignment.

**Visual notes** — `[visual: cut to B-roll]`, `[visual: lower-third graphic]`  
Notes for the video editor. Completely hidden from the teleprompter display and excluded from speech alignment. The tag must begin with `visual:` immediately after the opening bracket (case-insensitive).

Example combining both:

```
Hello and welcome. [pause] Today we are going to talk about [visual: insert product shot here] clean energy.
```

In the teleprompter, `[pause]` appears faded and italic; the `[visual: ...]` note is invisible.

## Known limitations

- Speech recognition requires an internet connection on some macOS versions depending on locale and on-device model availability.
- The alignment engine scans forward only; it will not jump backward if you re-read a section.
- Mirror/flip mode for use with reflective teleprompter hardware is a planned feature and not yet available in the initial release.
