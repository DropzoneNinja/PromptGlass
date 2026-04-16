# PROJECT.md

## Project Title

**PromptGlass** (working title)

A native **macOS SwiftUI teleprompter application** that helps a narrator read scripted text naturally while the app tracks spoken words in real time, highlights the current spoken word, keeps the reading position comfortably visible, records narration audio, and provides live visual feedback of the incoming audio signal.

---

## Goal

Build a polished, maintainable, native **macOS** application using **SwiftUI** that allows a user to:

1. Enter and edit script text.
2. Start a teleprompter session in a **floating, resizable window**.
3. Use live speech recognition / word alignment to determine which word is currently being spoken.
4. Visually **highlight the current spoken word**.
5. Automatically scroll the teleprompter so the current word remains near the **bottom of the top third** of the window.
6. Treat anything inside **square brackets `[ ... ]`** as stage directions or notes that are **not spoken words**.
7. If recognition drifts or misses words, **scan forward** in the script to find the best matching next position.
8. Record the incoming narration to an audio file.
9. Display an **elapsed time clock** during recording / prompting.
10. Display a **live audio level / waveform style visualization** of the microphone input.

This app should feel production-quality, readable, extensible, and architected so future features can be added cleanly.

---

## Platform and Technical Requirements

* **Platform:** macOS only
* **UI Framework:** SwiftUI
* **Language:** Swift
* **Minimum macOS target:** Prefer modern baseline, e.g. **macOS 14+** unless there is a compelling reason otherwise
* **Architecture:** MVVM or equivalent clean modular architecture
* **Audio:** AVFoundation
* **Speech Recognition:** Apple Speech framework first, with abstraction layer so engine can be replaced later
* **Persistence:** Local app storage for projects/scripts/settings using lightweight persistence (e.g. JSON, SwiftData, or file-based persistence)
* **Testing:** Unit tests for parser, tokenizer, alignment, and scroll targeting logic

---

## Product Summary

The application has two primary modes:

### 1. Script Editing Mode

The user writes or pastes in text, edits it, and prepares the script.

### 2. Prompting / Performance Mode

The script is displayed in a separate **floating teleprompter window** that can sit above other windows. As the narrator speaks:

* the current spoken word is highlighted,
* the text scrolls smoothly,
* non-spoken direction text in brackets is visually distinct and excluded from alignment,
* audio is recorded,
* a timer runs,
* microphone activity is visualized.

---

## Core Functional Requirements

## 1. Script Input and Editing

The app must provide a script editor where the user can:

* Create a new script
* Edit existing script text
* Paste large blocks of text
* Save and reopen scripts
* Optionally rename scripts/projects

Editor requirements:

* Comfortable large text editing area
* Monospaced or readable editor font
* Basic formatting is not required unless it helps implementation
* Support multiline text naturally
* Preserve bracketed direction text exactly as written

### Bracket Direction Rules

Any text inside square brackets is **directional / non-spoken** content.

Examples:

* `[pause]`
* `[look to camera 2]`
* `This is a line [smile] that continues.`

Rules:

* Bracketed segments should be rendered visually distinct in the teleprompter view.
* Bracketed segments must **not** be included as spoken words for speech alignment.
* Bracketed segments may still appear in the teleprompter display.
* Nested brackets do not need to be supported unless easy to implement; flat bracket parsing is acceptable.
* Unbalanced brackets should fail gracefully and be treated in a sensible way.

---

## 2. Floating Teleprompter Window

When the user starts a session, open a separate window dedicated to teleprompting.

Requirements:

* Floating / always-on-top behavior if possible on macOS
* Resizable window
* Clean, distraction-free presentation
* Large readable text
* Dark and light presentation support if appropriate, but default should favor teleprompter readability
* Window should remain interactive and performant during live recognition

Optional but desirable:

* Borderless or minimal chrome mode
* Fullscreen teleprompter mode
* Mirror / horizontal flip mode for use with reflective teleprompter hardware
* Adjustable font size and line spacing

---

## 3. Spoken Word Highlighting

The app must visually show the word currently being spoken.

Requirements:

* Highlight the current spoken word clearly
* Already-spoken words may optionally have a different visual treatment
* Future words remain readable but less emphasized
* Highlight transitions should feel smooth and stable
* Highlighting should be robust even when the recognition engine emits partial or imperfect hypotheses

Implementation concept:

* Parse the script into tokens
* Maintain a mapping from recognized spoken words to spoken-token indices
* Ignore direction tokens during alignment
* Drive the UI highlight from the current aligned spoken token index

Do not assume perfect 1:1 recognition. The system must tolerate:

* filler words,
* missed words,
* slightly incorrect words,
* repeated words,
* recognition lag,
* punctuation differences.

---

## 4. Auto-Scroll Behavior

The teleprompter must automatically scroll so the current spoken word stays near the **bottom of the top one-third of the visible area**.

Interpretation:

* If the teleprompter window height is `H`, the target vertical anchor should be roughly around `H * 0.30` to `H * 0.33` from the top.
* The current word should not remain centered; it should sit higher than center, leaving more upcoming text visible below.

Requirements:

* Smooth scrolling
* Avoid jitter from tiny recognition changes
* Avoid frequent back-and-forth adjustments
* Scroll only when needed once the highlighted word moves beyond tolerance bounds
* Recalculate correctly when the window is resized or font settings change

Suggested strategy:

* Compute layout metrics for lines/word bounds
* Determine the current word’s screen position
* Scroll only when current word drifts outside a target band around the desired anchor point
* Use damped or animated scrolling rather than abrupt snapping

---

## 5. Speech Tracking and Word Alignment

This is a critical feature.

The application must listen to the microphone and align live recognized speech to the script text.

### Recognition Requirements

* Use Apple Speech framework initially
* Support partial results continuously
* Continuously update current word location
* Handle recognition drift intelligently

### Script Parsing Model

The script should be tokenized into something like:

* visible spoken tokens
  n- visible non-spoken direction tokens
* punctuation / separators as needed

Need a clean internal representation, for example:

* `ScriptDocument`
* `ScriptSegment`
* `Token`
* `SpokenToken`
* `DirectionToken`

### Alignment Requirements

The recognizer output will not be perfect. The matching engine must:

* Compare normalized recognized words against normalized script words
* Ignore punctuation and case for alignment
* Ignore bracketed direction text completely when matching
* Permit near matches or fuzzy matching where reasonable
* Work incrementally as speech comes in

### Forward Scan Recovery Requirement

If the next expected word is not what the narrator is saying, the app must **scan forward** through the text and find the best candidate match.

This means:

* Do not hard-fail when the recognition stream diverges from the current cursor
* Search ahead within a configurable window of future spoken tokens
* Score candidate matches based on exact or fuzzy matches over one or more upcoming recognized words
* Advance to the best candidate if confidence is good enough
* Avoid jumping backward unless there is a strong reason and a specific design decision

A practical strategy:

* Maintain a current token cursor
* Given latest partial transcript tokens, compare against the next expected range
* If mismatch persists, search forward across the next N spoken tokens
* Use sequence similarity / sliding window matching on normalized tokens
* Pick the candidate with the best score above threshold
* Add hysteresis so it does not jump around too aggressively

Things to account for:

* repeated words in the script,
* common stop words,
* recognizer inserting or dropping words,
* narrator skipping sentences,
* narrator paraphrasing slightly.

Design this as a dedicated component, for example:

* `SpeechAlignmentEngine`

This engine should be testable independently of UI.

---

## 6. Audio Recording

The app must record the narration audio into a file.

Requirements:

* Start recording when prompting session starts, or provide a clear record toggle
* Save audio to a reasonable user-accessible app location
* Support a common format such as `.m4a` or `.caf`
* Surface recording errors clearly
* Allow the user to find or reveal the recorded file after the session

Desirable metadata:

* Timestamped filename
* Association with script/session name
* Session duration

Potential implementation:

* `AVAudioEngine` for live input monitoring
* `AVAudioFile` or `AVAudioRecorder` depending on chosen architecture

Need to ensure compatibility between:

* live speech recognition,
* live level metering / waveform,
* simultaneous recording.

Audio session / capture pipeline should be designed cleanly so the microphone stream can feed:

1. speech recognition,
2. level analysis / visualization,
3. file recording.

---

## 7. Elapsed Time Clock

Display an elapsed session timer during prompting.

Requirements:

* Starts when session starts
* Pauses / resumes correctly if supported
* Resets correctly on stop
* Clear, readable display in teleprompter mode

Potential format:

* `00:00`
* `01:23`
* `01:02:15` if long sessions are possible

---

## 8. Live Audio Visualization

Display a live visual representation of audio coming in.

Requirements:

* Real-time update
* Lightweight and visually clean
* Useful for confirming microphone input is present

Acceptable implementations:

* level meter bars
* waveform-style strip
* RMS / peak meter

Strong preference:

* Keep it elegant and low distraction
* Do not hurt teleprompter performance

Implementation idea:

* derive RMS / peak from audio buffers,
* smooth with decay,
* feed SwiftUI view model updates at a controlled refresh rate.

---

## User Experience Requirements

The app should feel polished and simple.

### Main Window UX

Should include:

* script list or document controls
* editor
* session controls
* perhaps settings for font size, prompt speed behavior, microphone input, etc.

### Teleprompter Window UX

Should include at minimum:

* script text
* live highlighted word
* elapsed timer
* live audio visualization
* recording indicator

Possible controls:

* Start / stop session
* Pause / resume
* Reset session position
* Toggle mirror mode
* Toggle always-on-top
* Adjust text size

---

## Non-Functional Requirements

* Code should be modular and maintainable
* Prefer small focused types over giant files
* Separate UI, services, parsing, alignment, audio, and persistence layers
* Avoid tightly coupling speech recognition directly into SwiftUI views
* Keep threading safe and explicit
* Use async/await where appropriate
* Handle permissions cleanly (microphone, speech recognition)
* Surface errors with clear user-facing messaging
* Keep UI responsive under continuous live updates

---

## Suggested Architecture

Use a clean modular structure such as:

```text
App/
  PromptGlassApp.swift

Models/
  ScriptDocument.swift
  ScriptToken.swift
  PromptSession.swift
  SessionSettings.swift

Views/
  MainEditorView.swift
  ScriptEditorView.swift
  TeleprompterView.swift
  AudioMeterView.swift
  TimerView.swift
  SessionControlsView.swift

ViewModels/
  ScriptEditorViewModel.swift
  TeleprompterViewModel.swift
  SessionViewModel.swift

Services/
  ScriptParser.swift
  SpeechRecognitionService.swift
  SpeechAlignmentEngine.swift
  AudioCaptureService.swift
  AudioRecordingService.swift
  ScrollCoordinator.swift
  PersistenceService.swift
  PermissionService.swift

Utilities/
  TextNormalization.swift
  FuzzyMatch.swift
  TimeFormatting.swift

Tests/
  ScriptParserTests.swift
  SpeechAlignmentEngineTests.swift
  TextNormalizationTests.swift
  ScrollCoordinatorTests.swift
```

This exact structure can change, but the separation of concerns should remain.

---

## Parsing Requirements

Implement a parser that transforms raw script text into structured content.

### Parser responsibilities

* Identify spoken text segments
* Identify bracketed direction segments
* Preserve original text for display
* Produce normalized spoken tokens for alignment
* Keep enough positional information to map token indices back to rendered text positions

### Token normalization

For matching purposes:

* lowercase
* strip punctuation where appropriate
* normalize apostrophes / quotes if useful
* preserve original display text separately from normalized match text

Example:

Raw:
`Hello there [smile] everyone.`

Display tokens:

* `Hello`
* `there`
* `[smile]`
* `everyone`

Spoken tokens used for matching:

* `hello`
* `there`
* `everyone`

---

## Alignment Engine Requirements

This is the most important logic in the application.

Claude should implement a practical, testable alignment engine rather than relying on simplistic “next word only” logic.

### Minimum behavior

* Maintain current script position
* Accept partial recognized text updates
* Normalize recognized tokens
* Compare recognized tokens against upcoming script spoken tokens
* Advance when matches occur
* Recover by scanning ahead on mismatch

### Good candidate strategy

A hybrid of:

* exact token matching,
* local sequence matching,
* fuzzy scoring,
* forward-only bias.

### Suggested scoring signals

* exact match bonus
* fuzzy / edit-distance similarity
* consecutive match streak bonus
* penalty for large jumps
* penalty for weak stop-word-only matches

### Recovery window

Make configurable, e.g. scan next 20–80 spoken tokens depending on transcript length and performance.

### Stability techniques

* confidence threshold before jumping forward
* require either multiple matching tokens or one strong unique token
* debounce alignment changes slightly to avoid flicker

### Important

Do not build this as a black box hidden in UI code. It must be independently unit tested with realistic examples.

---

## Scroll Coordination Requirements

Because the current highlighted word drives the scroll position, create a specific mechanism for scroll coordination.

### Needs

* Map current token / rendered word to location in view
* Determine whether scrolling is needed
* Animate toward target anchor position
* Be resilient to layout changes

Implementation may require:

* custom text layout handling,
* attributed text measurement,
* bridging to AppKit if needed,
* or a custom rendering strategy if pure SwiftUI text does not provide sufficient word-level geometry.

Claude should choose the most robust solution, even if it requires limited AppKit interop.

This is important: **word-level highlight plus controlled scrolling may be difficult with stock SwiftUI `Text` alone**. If necessary, use:

* NSTextView / TextKit interop,
* NSScrollView,
* NSAttributedString,
* custom layout measurement.

Correctness and smoothness matter more than staying 100% pure-SwiftUI in every leaf implementation. The app should still be architected as a SwiftUI app.

---

## Audio System Requirements

Claude should design the audio path carefully.

### Responsibilities

* request microphone permission
* capture mic input
* feed speech recognition
* compute live levels / waveform data
* record to file

Potential services:

* `AudioCaptureService`
* `AudioMeterProcessor`
* `AudioRecordingService`
* `SpeechRecognitionService`

These can share a single input pipeline where possible.

### Performance considerations

* do not update waveform UI at raw audio callback rate
* throttle UI updates to a sensible refresh rate
* avoid blocking audio threads

---

## Permissions

The app requires at least:

* Microphone permission
* Speech Recognition permission

Requirements:

* request clearly
* explain why access is needed
* handle denied state gracefully
* provide guidance if user must enable permission manually in System Settings

---

## Data Persistence

At minimum, persist:

* scripts/documents
* basic app/session settings
* perhaps last-opened script

Desirable settings:

* font size
* line spacing
* theme
* mirror mode
* always-on-top preference
* scroll smoothing preferences
* selected microphone input if feasible

---

## Suggested UI Layout

## Main Window

Potential layout:

* Left sidebar: scripts/projects
* Center: text editor
* Top/right toolbar: new, save, delete, start session
* Bottom or side inspector: session settings

Suggested settings:

* font size
* line spacing
* highlight style
* mirror mode toggle
* recording toggle
* microphone selection if available

## Teleprompter Window

Potential layout:

* Main area: large script text
* Overlay header/footer with:

  * elapsed time
  * recording status
  * audio meter
  * perhaps minimal controls

Need to keep the teleprompter clean and easy to read.

---

## Error Handling

The app should handle and communicate errors such as:

* microphone unavailable
* speech recognition unavailable
* permission denied
* audio recording failed
* failed to save script
* corrupted saved data

User-facing error messages should be friendly and actionable.

---

## Testing Requirements

Claude should include meaningful tests.

### Must-have tests

1. **ScriptParserTests**

   * bracketed direction parsing
   * mixed spoken and direction text
   * malformed brackets behavior
   * normalization output

2. **SpeechAlignmentEngineTests**

   * exact progression
   * missed word recovery
   * scan-forward recovery
   * repeated word scenarios
   * punctuation / case insensitivity
   * direction token skipping

3. **ScrollCoordinatorTests**

   * target anchor calculations
   * no-scroll tolerance band behavior
   * resize recalculation behavior

4. **Time formatting and utility tests** where useful

Where UI-specific logic cannot easily be unit-tested, keep logic extracted into plain Swift types that can.

---

## Example Scenarios Claude Should Support

### Scenario 1: Straight read

Script:
`Hello and welcome to the show.`

Expected:

* highlight advances word by word
* scroll follows smoothly
* audio records
* timer runs

### Scenario 2: Directions in brackets

Script:
`Hello [smile] and welcome to the show.`

Expected:

* `[smile]` displayed distinctly
* `[smile]` excluded from spoken alignment
* if narrator says “Hello and welcome...”, matching continues correctly

### Scenario 3: Recognition miss, then recovery

Script:
`Today we are going to talk about the future of clean energy.`

Recognizer temporarily misses “going to”.

Expected:

* alignment does not stall permanently
* engine recovers by matching later words like “talk”, “future”, “energy” within a forward scan window

### Scenario 4: Skipped sentence

Narrator jumps ahead in the script.

Expected:

* engine eventually locks onto a future location rather than staying stuck on the old line forever

---

## Implementation Notes for Claude

* Favor correctness and maintainability over shortcuts.
* If SwiftUI text rendering alone is insufficient for per-word highlighting and scroll targeting, bridge to AppKit cleanly.
* Keep core logic independent from UI.
* Avoid giant god objects.
* Use protocols where useful, especially around speech recognition and persistence.
* Document any tradeoffs.
* Add comments where implementation is non-obvious, especially in the alignment logic.
* Keep naming clean and consistent.
* Prefer a polished, modern macOS experience rather than an iOS-style UI transplanted onto desktop.

---

## Deliverables

Claude should produce:

1. A complete SwiftUI macOS app project
2. Clean architecture with separated services and view models
3. Script editing UI
4. Floating teleprompter window
5. Live spoken word highlighting
6. Scroll-follow behavior with target anchor near lower edge of top third
7. Bracket direction parsing and exclusion from spoken matching
8. Scan-forward recovery alignment logic
9. Audio recording to file
10. Elapsed timer UI
11. Live audio visualization UI
12. Persistence for scripts/settings
13. Permission handling
14. Unit tests for core logic
15. Clear README with build/run notes and known limitations

---

## Nice-to-Have Features

These are optional and should be added only if they do not compromise the core implementation:

* mirrored teleprompter mode
* fullscreen mode
* keyboard shortcuts
* multiple scripts/projects
* export / import scripts
* session history
* adjustable colors/themes
* confidence indicator for recognition alignment
* optional manual nudge controls for moving current position forward/backward

---

## Out of Scope for Initial Version

To keep the first version achievable, these are not required unless easy:

* cloud sync
* collaboration
* rich text formatting
* video recording
* multiple simultaneous audio tracks
* speaker diarization
* AI rewriting features

---

## Definition of Done

The project is done when:

* the user can create/edit/save a script,
* open a teleprompter window,
* speak into the mic,
* see the currently spoken word highlighted,
* see the text smoothly scroll to keep the current word in the intended region,
* bracketed directions remain visible but are excluded from spoken matching,
* the alignment engine can recover by scanning forward,
* audio is recorded successfully,
* elapsed time and live audio visualization are visible,
* the codebase is clean and testable,
* and the project builds and runs reliably on macOS.

---

## Final Instruction to Claude

Build this as if it is a real product, not a prototype hack. Prioritize robust script parsing, stable alignment, readable architecture, and a polished native macOS user experience.
