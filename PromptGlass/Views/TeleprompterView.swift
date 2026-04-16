import AppKit
import SwiftUI

// MARK: - TeleprompterView

/// Full-window content for the floating teleprompter.
///
/// ## Layout
/// ```
/// ┌──────────────────────────────────────────┐
/// │  [00:00]          [● REC]  [▬▬▬▬▬▬▬▬▬]  │ ← top bar (always visible)
/// │                                          │
/// │   Script text flows here, with the       │
/// │   current word highlighted in teal.      │
/// │   Past words are dim; future words are   │
/// │   white.  [Direction tokens] are italic  │
/// │   and muted.                             │
/// │                                          │
/// │  ┌────────────────────────────────────┐  │
/// │  │ A⁻ 36pt A⁺ | ⇄ | ‖ Pause  ◼ Stop │  │ ← controls bar (auto-hides)
/// │  └────────────────────────────────────┘  │
/// └──────────────────────────────────────────┘
/// ```
///
/// ## Threading / observation
/// Both `teleprompterVM` and `sessionVM` are `@Observable` and `@MainActor`,
/// so SwiftUI automatically re-renders whenever their published properties change.
/// `currentSpokenIndex` changes drive `tokenIndexDidChange()` (→ `ScrollCoordinator`)
/// via `onChange(of:)`.
struct TeleprompterView: View {

    var teleprompterVM: TeleprompterViewModel
    var sessionVM: SessionViewModel

    // MARK: - Private state

    /// Whether the bottom controls bar is currently visible.
    @State private var showControls = true

    /// Timer that hides controls after 3 s of inactivity.
    @State private var hideTask: Task<Void, Never>?

    /// Drives the session-error alert when a mid-session failure is surfaced
    /// by `SessionViewModel` — e.g. mic unplugged or recognition task failure.
    @State private var showErrorAlert = false

    /// Drives the brief flash animation on the clap marker button.
    @State private var clapFlashing = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // ── Background ─────────────────────────────────────────────────
            Color(nsColor: .init(white: 0.07, alpha: 1.0))
                .ignoresSafeArea()

            // ── Space-bar shortcut (always present, invisible) ──────────────
            spaceBarShortcuts

            // ── Main column: top bar + text view ────────────────────────────
            VStack(spacing: 0) {
                // Top bar occupies its own row — never overlaps text.
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // Script text fills the remaining space below the top bar.
                // Reading `scrollTarget` here creates an @Observable dependency so
                // SwiftUI calls updateNSView whenever the coordinator sets a new target.
                let _ = teleprompterVM.scrollTarget   // dependency registration
                GeometryReader { geo in
                    TeleprompterTextView(
                        tokens:             teleprompterVM.tokens,
                        currentSpokenIndex: teleprompterVM.currentSpokenIndex,
                        fontSize:           sessionVM.settings.fontSize,
                        lineSpacing:        sessionVM.settings.lineSpacing,
                        mirrorMode:         sessionVM.settings.mirrorMode,
                        scrollCoordinator:  teleprompterVM.scrollCoordinator,
                        containerWidth:     geo.size.width
                    )
                }
                // Reserve space for the persistent clap marker strip.
                Color.clear
                    .frame(height: sessionVM.isActive ? 52 : 0)
                    .animation(.easeInOut(duration: 0.2), value: sessionVM.isActive)
                // Reserve space so the bottom controls bar never covers text.
                Color.clear
                    .frame(height: showControls ? 68 : 14)
                    .animation(.easeInOut(duration: 0.2), value: showControls)
            }

            // ── Bottom overlay: persistent clap strip + auto-hiding controls ─
            VStack(spacing: 0) {
                Spacer()
                clapMarkerStrip
                    .padding(.bottom, showControls ? 4 : 14)
                    .animation(.easeInOut(duration: 0.2), value: showControls)
                if showControls {
                    controlsBar
                        .padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showControls)
        }
        // Advance ScrollCoordinator whenever the spoken cursor moves.
        .onChange(of: teleprompterVM.currentSpokenIndex) { _, _ in
            teleprompterVM.tokenIndexDidChange()
        }
        // Show controls briefly whenever the session state changes.
        .onChange(of: sessionVM.session.state) { _, _ in
            revealControls()
        }
        // Reveal controls when the mouse moves over the window.
        .onContinuousHover { phase in
            if case .active = phase { revealControls() }
        }
        // Surface session errors (mic interruption, recognition failure, etc.)
        // in the teleprompter window — which may be the only visible window
        // during a performance.
        .alert("Session Error", isPresented: $showErrorAlert) {
            Button("OK") { }
        } message: {
            Text(sessionVM.sessionError ?? "An unexpected error occurred.")
        }
        .onChange(of: sessionVM.sessionError) { _, newError in
            if newError != nil { showErrorAlert = true }
        }
    }

    // MARK: - Space bar keyboard shortcuts

    /// Zero-size invisible buttons that register space-bar shortcuts for
    /// pause / resume regardless of whether the auto-hiding controls bar is
    /// currently visible.  Keyboard shortcuts are registered by SwiftUI through
    /// the responder chain, not through hit-testing, so zero-size is fine.
    @ViewBuilder
    private var spaceBarShortcuts: some View {
        if sessionVM.isRunning {
            Button("") { sessionVM.pause() }
                .keyboardShortcut(.space, modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)
        } else if sessionVM.isPaused {
            Button("") { sessionVM.resume() }
                .keyboardShortcut(.space, modifiers: [])
                .frame(width: 0, height: 0)
                .opacity(0)
        }
    }

    // MARK: - Top bar

    /// Always-visible strip at the top: timer + optional recording dot + meter.
    private var topBar: some View {
        HStack(spacing: 12) {
            TimerView(elapsed: sessionVM.formattedElapsedTime)
            Spacer()
            if sessionVM.isActive {
                RecordingIndicatorView()
            }
            AudioMeterView(level: teleprompterVM.audioLevel)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Controls bar (auto-hiding)

    /// Translucent bottom overlay with font-size, mirror, and session controls.
    private var controlsBar: some View {
        HStack(spacing: 14) {

            // Font size stepper
            fontSizeControl

            controlDivider

            // Mirror toggle
            mirrorButton

            controlDivider

            // Session lifecycle buttons
            sessionButtons

            if sessionVM.recordingURL != nil {
                controlDivider
                revealButton
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 10, y: 3)
        .padding(.horizontal, 20)
    }

    // MARK: - Font size

    private var fontSizeControl: some View {
        HStack(spacing: 6) {
            Button {
                sessionVM.settings.fontSize = max(18, sessionVM.settings.fontSize - 2)
            } label: {
                Image(systemName: "textformat.size.smaller")
                    .controlSize(.small)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .help("Decrease font size")

            Text("\(Int(sessionVM.settings.fontSize)) pt")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .frame(minWidth: 36)

            Button {
                sessionVM.settings.fontSize = min(72, sessionVM.settings.fontSize + 2)
            } label: {
                Image(systemName: "textformat.size.larger")
                    .controlSize(.small)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .help("Increase font size")
        }
    }

    // MARK: - Mirror

    private var mirrorButton: some View {
        Button {
            sessionVM.settings.mirrorMode.toggle()
        } label: {
            Image(
                systemName: sessionVM.settings.mirrorMode
                    ? "arrow.left.and.right.righttriangle.left.righttriangle.right.fill"
                    : "arrow.left.and.right.righttriangle.left.righttriangle.right"
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(sessionVM.settings.mirrorMode ? Color.accentColor : .white)
        .help(sessionVM.settings.mirrorMode ? "Disable mirror mode" : "Enable mirror mode")
    }

    // MARK: - Session controls

    @ViewBuilder
    private var sessionButtons: some View {
        switch sessionVM.session.state {

        case .idle, .stopped:
            Button("Reset") { sessionVM.reset() }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.8))

        case .running:
            Button {
                sessionVM.pause()
            } label: {
                Label("Pause", systemImage: "pause.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)

            Button {
                sessionVM.stop()
            } label: {
                Label("Stop", systemImage: "stop.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.red.opacity(0.9))

            Button("Reset") { sessionVM.reset() }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))

        case .paused:
            Button {
                sessionVM.resume()
            } label: {
                Label("Resume", systemImage: "play.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.green)

            Button {
                sessionVM.stop()
            } label: {
                Label("Stop", systemImage: "stop.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.red.opacity(0.9))

            Button("Reset") { sessionVM.reset() }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Reveal recording in Finder

    private var revealButton: some View {
        Button {
            sessionVM.revealRecordingInFinder()
        } label: {
            Label("Show Recording", systemImage: "folder")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.7))
        .help("Reveal recording in Finder")
    }

    // MARK: - Clap marker strip

    /// Always-visible full-width button shown whenever a session is active.
    /// Tapping injects a double-impulse clapperboard transient into the recording
    /// so editors can quickly locate sync points in the waveform.
    @ViewBuilder
    private var clapMarkerStrip: some View {
        if sessionVM.isActive {
            Button {
                sessionVM.insertClapMarker()
                triggerClapFlash()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clapperboard")
                    Text("Clap Marker")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(clapFlashing
                              ? Color.white.opacity(0.30)
                              : Color.white.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                )
                .animation(.easeOut(duration: 0.15), value: clapFlashing)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .help("Insert a clapperboard sync marker into the recording")
        }
    }

    private func triggerClapFlash() {
        clapFlashing = true
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)   // 150 ms
            clapFlashing = false
        }
    }

    // MARK: - Controls auto-hide

    private var controlDivider: some View {
        Divider()
            .frame(height: 18)
            .overlay(Color.white.opacity(0.25))
    }

    private func revealControls() {
        hideTask?.cancel()
        withAnimation { showControls = true }

        // Keep controls visible indefinitely after a session stops so the user
        // can always reach the "Show Recording" button (and Reset).
        let state = sessionVM.session.state
        guard state != .stopped && state != .idle else { return }

        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)   // 3 s
            guard !Task.isCancelled else { return }
            withAnimation { showControls = false }
        }
    }
}

// MARK: - TeleprompterWindowController

/// Opens and manages a floating `NSWindow` containing `TeleprompterView`.
///
/// The window uses `.floating` level so it stays above other applications —
/// matching teleprompter hardware conventions. It is resizable and closable.
///
/// Call `open(…)` when a session starts and `close()` when it ends.
@MainActor
final class TeleprompterWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?

    // MARK: - Open

    /// Opens the teleprompter window if it is not already visible.
    func open(teleprompterVM: TeleprompterViewModel, sessionVM: SessionViewModel) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = TeleprompterView(
            teleprompterVM: teleprompterVM,
            sessionVM:      sessionVM
        )

        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = .minSize

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask:   [.titled, .closable, .resizable, .miniaturizable,
                          .fullSizeContentView],
            backing:     .buffered,
            defer:       false
        )
        win.title                          = "PromptGlass"
        win.titlebarAppearsTransparent     = true
        win.isMovableByWindowBackground    = true
        win.backgroundColor                = NSColor(white: 0.07, alpha: 1.0)
        win.contentView                    = hosting
        win.level                          = .floating
        win.isReleasedWhenClosed           = false
        win.delegate                       = self
        win.setFrameAutosaveName("TeleprompterWindow")

        // Restore saved position or centre on first launch.
        if !win.setFrameUsingName("TeleprompterWindow") {
            win.center()
        }

        win.makeKeyAndOrderFront(nil)
        self.window = win
    }

    // MARK: - Close

    /// Closes the teleprompter window and releases the `NSWindow` reference.
    func close() {
        window?.close()
        window = nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
