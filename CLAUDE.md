# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**PromptGlass** — a native macOS SwiftUI teleprompter app. The narrator edits a script, starts a session, and the app uses live speech recognition to highlight the currently spoken word and auto-scroll the teleprompter to keep it readable.

Full specification: [PROJECT.md](PROJECT.md)

## Build & Test

The project must be structured as an Xcode project (`.xcodeproj`) so it can be opened and compiled directly in Xcode.

```bash
# Build (Debug)
xcodebuild -project PromptGlass.xcodeproj -scheme PromptGlass -configuration Debug build

# Run all tests
xcodebuild test -project PromptGlass.xcodeproj -scheme PromptGlass -destination 'platform=macOS'

# Run a single test class
xcodebuild test -project PromptGlass.xcodeproj -scheme PromptGlass \
  -destination 'platform=macOS' \
  -only-testing:PromptGlassTests/SpeechAlignmentEngineTests

# Run a single test method
xcodebuild test -project PromptGlass.xcodeproj -scheme PromptGlass \
  -destination 'platform=macOS' \
  -only-testing:PromptGlassTests/SpeechAlignmentEngineTests/testScanForwardRecovery
```

**Minimum deployment target:** macOS 14

## Architecture

Two primary modes: **Script Editing** (main window) and **Prompting/Performance** (floating teleprompter window).

### Layer structure

```
Views/          SwiftUI views only — no business logic
ViewModels/     @Observable or ObservableObject; bridge services to views
Services/       All non-UI logic; must be independently testable
Models/         Plain data types (ScriptDocument, ScriptToken, PromptSession, SessionSettings)
Utilities/      Stateless helpers (TextNormalization, FuzzyMatch, TimeFormatting)
Tests/          Unit tests for Services and Utilities
```

### Critical services

**`SpeechAlignmentEngine`** — the most important component. Maintains a cursor into the script's spoken tokens, accepts partial `SFSpeechRecognitionResult` updates, and advances via forward-scan recovery when recognition drifts. Never jumps backward. Must be unit-tested independently of any UI. Key behaviors:
- Normalize both script tokens and recognized tokens (lowercase, strip punctuation) before comparing
- On mismatch, scan forward up to a configurable window (20–80 spoken tokens)
- Score candidates with: exact match bonus, fuzzy/edit-distance similarity, consecutive-match streak bonus, large-jump penalty
- Require confidence threshold before committing a forward jump (debounce to avoid flicker)

**`ScriptParser`** — tokenizes raw script text into `SpokenToken` and `DirectionToken`. Text inside `[square brackets]` is a direction token: displayed visually distinct, excluded from alignment matching. Normalization must separate display text from match text.

**`ScrollCoordinator`** — maps current token index to a rendered position and scrolls so that word lands at ~30–33% from the top of the teleprompter window. Pure SwiftUI `Text` does not provide per-word geometry; use `NSTextView`/`TextKit`/`NSAttributedString` interop where needed. Scroll only when the current word drifts outside a tolerance band; use animated, damped scrolling.

**Audio pipeline** — a single `AVAudioEngine` tap feeds three consumers to avoid competing mic captures:
1. `SpeechRecognitionService` — wraps `SFSpeechRecognizer` behind a protocol (`SpeechRecognizing`) so the engine is swappable
2. `AudioMeterProcessor` — computes RMS/peak for the waveform visualization; throttles UI updates to a sensible refresh rate (do not update at raw audio callback rate)
3. `AudioRecordingService` — writes `.m4a`/`.caf` to a timestamped file in the app's support directory

### Speech recognition requirement

**Must use Apple's native `Speech` framework (`SFSpeechRecognizer`)** — no third-party ASR libraries. Wrap it behind a `SpeechRecognizing` protocol so the implementation can be replaced without changing calling code.

### AppKit interop

The app is architected as SwiftUI-first, but AppKit interop is explicitly permitted (and expected) for:
- Per-word layout geometry in the teleprompter view
- Scroll control (`NSScrollView`)
- Rich text rendering (`NSAttributedString`, `NSTextView`)

Wrap AppKit components in `NSViewRepresentable` / `NSViewControllerRepresentable` to keep them composable within SwiftUI.

### Threading

Use `async/await`. Audio callbacks run on dedicated audio threads — never update `@MainActor` state directly from an audio tap; dispatch back to the main actor.

## Permissions

The app requires **Microphone** and **Speech Recognition** entitlements. Both must be requested at runtime with clear usage descriptions. Handle denied/restricted state gracefully and direct the user to System Settings.

## Tests to maintain

| Test target | What it covers |
|---|---|
| `ScriptParserTests` | Bracket parsing, mixed content, malformed brackets, normalization output |
| `SpeechAlignmentEngineTests` | Exact progression, missed-word recovery, scan-forward, repeated words, direction-token skipping |
| `ScrollCoordinatorTests` | Anchor calculations, no-scroll tolerance band, resize recalculation |
| Utility tests | `TextNormalization`, `TimeFormatting` |

Keep core logic in plain Swift types (no `UIKit`/`AppKit` imports) so tests run without a display.
