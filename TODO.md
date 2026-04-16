# PromptGlass — Implementation TODO

## Phase 1: Project Setup

- [x] Create Xcode project (`PromptGlass.xcodeproj`) targeting macOS 14+
- [x] Set up folder structure: `App/`, `Models/`, `Views/`, `ViewModels/`, `Services/`, `Utilities/`, `Tests/`
- [x] Configure entitlements: Microphone, Speech Recognition
- [x] Add `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` to Info.plist
- [x] Create test target (`PromptGlassTests`)

---

## Phase 2: Models

- [x] `ScriptToken` — base type with display text and kind (spoken / direction)
- [x] `SpokenToken` — normalized match text + display text + index
- [x] `DirectionToken` — bracketed display text
- [x] `ScriptDocument` — id, name, raw text, parsed token array
- [x] `PromptSession` — session state, current token index, elapsed time, recording path
- [x] `SessionSettings` — font size, line spacing, mirror mode, always-on-top, scroll smoothing

---

## Phase 3: Utilities

- [x] `TextNormalization` — lowercase, strip punctuation, normalize apostrophes
- [x] `FuzzyMatch` — edit-distance / similarity scoring between token strings
- [x] `TimeFormatting` — `MM:SS` / `HH:MM:SS` formatter
- [x] Unit tests for all three utilities

---

## Phase 4: Script Parser

- [x] Tokenize raw text into `SpokenToken` and `DirectionToken` segments
- [x] Handle `[bracket]` detection including inline brackets mid-sentence
- [x] Graceful handling of unbalanced brackets
- [x] Preserve original display text separately from normalized match text
- [x] `ScriptParserTests`
  - [x] Bracket parsing
  - [x] Mixed spoken + direction content
  - [x] Malformed / unbalanced brackets
  - [x] Normalization output matches expected tokens

---

## Phase 5: Persistence

- [x] `PersistenceService` — save/load `ScriptDocument` array (JSON or SwiftData)
- [x] Save/load `SessionSettings`
- [x] Track last-opened script
- [x] Handle corrupted/missing data gracefully

---

## Phase 6: Permissions

- [x] `PermissionService` — request microphone permission via `AVCaptureDevice`
- [x] Request speech recognition authorization via `SFSpeechRecognizer`
- [x] Expose combined permission state to ViewModels
- [x] Handle denied/restricted state with guidance to System Settings

---

## Phase 7: Audio Pipeline

- [x] `AudioCaptureService` — start/stop `AVAudioEngine`, install single input tap
- [x] `AudioMeterProcessor` — compute RMS/peak from tap buffers; throttle UI updates
- [x] `AudioRecordingService` — write `.m4a` to timestamped file in app support directory; expose file URL on stop
- [x] Verify single tap feeds all three consumers (recognition, metering, recording) without conflict
- [x] Handle audio engine interruptions and errors

---

## Phase 8: Speech Recognition Service

- [x] Define `SpeechRecognizing` protocol (start, stop, partial result callback)
- [x] `SpeechRecognitionService` — implements protocol using `SFSpeechRecognizer` + `SFSpeechAudioBufferRecognitionRequest`
- [x] Feed audio buffers from `AudioCaptureService` tap into recognition request
- [x] Emit partial `[String]` token arrays to alignment engine via callback/AsyncStream

---

## Phase 9: Speech Alignment Engine

- [x] Maintain current spoken-token cursor into parsed script
- [x] Accept incremental partial-result token arrays
- [x] Normalize incoming recognized tokens before comparison
- [x] Advance cursor on exact or fuzzy match
- [x] Forward-scan recovery: search next N tokens (configurable window) on mismatch
- [x] Scoring: exact match bonus, fuzzy similarity, consecutive-streak bonus, large-jump penalty, stop-word penalty
- [x] Confidence threshold before committing a forward jump
- [x] Debounce cursor changes to suppress flicker
- [x] Never jump backward
- [x] `SpeechAlignmentEngineTests`
  - [x] Exact word-by-word progression
  - [x] Missed-word recovery (scan forward)
  - [x] Skipped-sentence recovery
  - [x] Repeated-word scenarios
  - [x] Punctuation and case insensitivity
  - [x] Direction tokens excluded from matching

---

## Phase 10: Scroll Coordinator

- [x] Map current token index to rendered word position via TextKit/`NSTextView`
- [x] Compute target scroll offset so current word sits at ~30–33% from top
- [x] Scroll only when word drifts outside tolerance band
- [x] Animated, damped scrolling (no abrupt snapping)
- [x] Recalculate on window resize or font/spacing change
- [x] `ScrollCoordinatorTests`
  - [x] Target anchor calculations
  - [x] No-scroll tolerance band behavior
  - [x] Resize recalculation

---

## Phase 11: ViewModels

- [x] `ScriptEditorViewModel` — script list, CRUD operations, selected script, dirty state
- [x] `TeleprompterViewModel` — current token index, highlight state, scroll target, audio meter level
- [x] `SessionViewModel` — session lifecycle (start/pause/stop/reset), elapsed time ticker, recording state

---

## Phase 12: Main Window UI

- [x] `MainEditorView` — sidebar script list + center editor layout
- [x] `ScriptEditorView` — multiline text editor, monospaced/readable font
- [x] `SessionControlsView` — Start Session button, font size, line spacing, mirror toggle, mic selection
- [x] Script CRUD: new, rename, delete, save indicator

---

## Phase 13: Teleprompter Window UI

- [x] `TeleprompterView` — floating, always-on-top, resizable window
- [x] Render tokens with per-word highlight (current word) and past/future visual treatment
- [x] Direction tokens rendered visually distinct (e.g. dimmed, italicized)
- [x] `NSViewRepresentable` wrapper for `NSScrollView`/`NSTextView` word-level rendering
- [x] Mirror / horizontal flip mode
- [x] `AudioMeterView` — live waveform/level bar
- [x] `TimerView` — `MM:SS` / `HH:MM:SS` elapsed display
- [x] Recording indicator
- [x] Overlay controls: start/stop, pause/resume, reset, font size adjust, mirror toggle

---

## Phase 14: Wire Everything Together

- [x] `PromptGlassApp.swift` — app entry point, window management, environment objects
- [x] Connect `AudioCaptureService` → `SpeechRecognitionService` → `SpeechAlignmentEngine` → `TeleprompterViewModel`
- [x] Connect `AudioCaptureService` → `AudioMeterProcessor` → `TeleprompterViewModel`
- [x] Connect `AudioCaptureService` → `AudioRecordingService`
- [x] Session start/stop coordinates all services atomically
- [x] Surface recording file URL to user (reveal in Finder)

---

## Phase 15: Error Handling & Polish

- [x] Microphone unavailable / permission denied messaging
- [x] Speech recognition unavailable messaging
- [x] Audio recording failure messaging
- [x] Script save/load failure messaging
- [x] Responsive UI under continuous live recognition updates
- [x] Keyboard shortcuts for common actions

---

## Phase 16: Final Verification

- [ ] Scenario: straight read — highlight advances word by word, scroll follows, audio records, timer runs
- [ ] Scenario: inline direction — `[smile]` displayed distinct, excluded from alignment
- [ ] Scenario: recognition miss then recovery — engine scans forward and re-locks
- [ ] Scenario: narrator skips ahead — engine eventually locks onto future location
- [ ] All unit tests passing
- [ ] Project opens and compiles cleanly in Xcode
