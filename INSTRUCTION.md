# PromptGlass — Build & Run Instructions

## Prerequisites

- **Xcode 15 or later** installed from the Mac App Store  
- **macOS 14 (Sonoma) or later**  
- Command-line tools active:  
  ```bash
  xcode-select --install
  ```

Open a Terminal in the project root (`/Volumes/Data/Development/visualprompt`) for all commands below.

---

## 1. Running for Testing (Debug build)

### Option A — From Xcode (recommended for active development)

1. Open the project in Xcode:
   ```bash
   open PromptGlass.xcodeproj
   ```
2. In the toolbar, select the **PromptGlass** scheme and **My Mac** as the run destination.
3. Press **⌘R** (or Product → Run).

Xcode builds the app, launches it directly, and attaches the debugger. Console output and crash logs appear in the Debug area at the bottom.

---

### Option B — From the Terminal

**Build:**
```bash
xcodebuild \
  -project PromptGlass.xcodeproj \
  -scheme PromptGlass \
  -configuration Debug \
  build
```

**Find the built app** (the path is printed at the end of the build output, and is always under DerivedData):
```bash
xcodebuild \
  -project PromptGlass.xcodeproj \
  -scheme PromptGlass \
  -configuration Debug \
  -showBuildSettings \
  | grep "BUILT_PRODUCTS_DIR"
```

**Launch it:**
```bash
open "$(xcodebuild -project PromptGlass.xcodeproj -scheme PromptGlass -configuration Debug -showBuildSettings | grep BUILT_PRODUCTS_DIR | awk '{print $3}')/PromptGlass.app"
```

Or as a one-liner that builds and immediately launches:
```bash
xcodebuild -project PromptGlass.xcodeproj -scheme PromptGlass -configuration Debug build \
  && open "$(xcodebuild -project PromptGlass.xcodeproj -scheme PromptGlass -configuration Debug -showBuildSettings 2>/dev/null | grep BUILT_PRODUCTS_DIR | awk '{print $3}')/PromptGlass.app"
```

---

### Running the test suite

```bash
# All tests
xcodebuild test \
  -project PromptGlass.xcodeproj \
  -scheme PromptGlass \
  -destination 'platform=macOS'

# One test class
xcodebuild test \
  -project PromptGlass.xcodeproj \
  -scheme PromptGlass \
  -destination 'platform=macOS' \
  -only-testing:PromptGlassTests/SpeechAlignmentEngineTests

# One test method
xcodebuild test \
  -project PromptGlass.xcodeproj \
  -scheme PromptGlass \
  -destination 'platform=macOS' \
  -only-testing:PromptGlassTests/SpeechAlignmentEngineTests/testScanForwardRecovery
```

---

## 2. Building for Installation on Your Mac (Release build)

### Step 1 — Build a Release binary

```bash
xcodebuild \
  -project PromptGlass.xcodeproj \
  -scheme PromptGlass \
  -configuration Release \
  build
```

The compiled app bundle is written to DerivedData. Find the exact path with:

```bash
xcodebuild \
  -project PromptGlass.xcodeproj \
  -scheme PromptGlass \
  -configuration Release \
  -showBuildSettings \
  | grep BUILT_PRODUCTS_DIR
```

It will look something like:  
`~/Library/Developer/Xcode/DerivedData/PromptGlass-<hash>/Build/Products/Release/`

### Step 2 — Copy the app to /Applications

```bash
BUILD_DIR=$(xcodebuild \
  -project PromptGlass.xcodeproj \
  -scheme PromptGlass \
  -configuration Release \
  -showBuildSettings 2>/dev/null \
  | grep BUILT_PRODUCTS_DIR \
  | awk '{print $3}')

cp -R "$BUILD_DIR/PromptGlass.app" /Applications/
```

If an older copy is already in `/Applications/`, remove it first:
```bash
rm -rf /Applications/PromptGlass.app
cp -R "$BUILD_DIR/PromptGlass.app" /Applications/
```

### Step 3 — First launch and Gatekeeper

Because the app is signed with an ad-hoc identity (no Apple Developer account), macOS Gatekeeper will block the first launch with a "cannot be opened because it is from an unidentified developer" message.

**To allow it:**

1. Try to open the app: double-click `/Applications/PromptGlass.app`.  
   Gatekeeper will block it and show a warning dialog.
2. Open **System Settings → Privacy & Security**.
3. Scroll to the **Security** section.  
   You will see a message: *"PromptGlass was blocked from use because it is not from an identified developer."*
4. Click **Open Anyway**.
5. A second confirmation dialog appears — click **Open**.

This only needs to be done once. Subsequent launches open normally.

Alternatively, bypass Gatekeeper from the Terminal (also a one-time step):
```bash
xattr -dr com.apple.quarantine /Applications/PromptGlass.app
```

### Step 4 — Grant permissions on first run

The app requires two system permissions. macOS will prompt for each the first time a session is started:

- **Microphone** — needed to capture your voice.  
- **Speech Recognition** — needed to follow your narration.

Click **Allow** for both when prompted. If you accidentally deny one, go to  
**System Settings → Privacy & Security → Microphone** (or **Speech Recognition**)  
and re-enable PromptGlass there.

---

## Quick-reference command summary

| Goal | Command |
|---|---|
| Open in Xcode | `open PromptGlass.xcodeproj` |
| Debug build (terminal) | `xcodebuild -project PromptGlass.xcodeproj -scheme PromptGlass -configuration Debug build` |
| Release build | `xcodebuild -project PromptGlass.xcodeproj -scheme PromptGlass -configuration Release build` |
| Run all tests | `xcodebuild test -project PromptGlass.xcodeproj -scheme PromptGlass -destination 'platform=macOS'` |
| Remove quarantine flag | `xattr -dr com.apple.quarantine /Applications/PromptGlass.app` |
