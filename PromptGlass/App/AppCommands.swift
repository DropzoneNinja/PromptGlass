import SwiftUI

// MARK: - FocusedValueKey definitions

/// Exposes the `ScriptEditorViewModel` to menu-bar `Commands` via
/// `focusedSceneValue(\.editorViewModel, editorVM)` in `ContentView`.
private struct EditorVMKey: FocusedValueKey {
    typealias Value = ScriptEditorViewModel
}

/// Exposes the `SessionViewModel` to menu-bar `Commands` via
/// `focusedSceneValue(\.sessionViewModel, sessionVM)` in `ContentView`.
private struct SessionVMKey: FocusedValueKey {
    typealias Value = SessionViewModel
}

extension FocusedValues {
    var editorViewModel: ScriptEditorViewModel? {
        get { self[EditorVMKey.self] }
        set { self[EditorVMKey.self] = newValue }
    }

    var sessionViewModel: SessionViewModel? {
        get { self[SessionVMKey.self] }
        set { self[SessionVMKey.self] = newValue }
    }
}

// MARK: - App-level menu commands

/// PromptGlass menu-bar commands.
///
/// Replaces the default SwiftUI "New Window" File-menu item with
/// "New Script", and adds a "Session" menu with keyboard shortcuts for
/// the full session lifecycle.
///
/// View models are accessed via `@FocusedValue` — they are injected by
/// `ContentView` using `.focusedSceneValue`. All button actions guard against
/// a nil VM and defer to the VM's own guard clauses for invalid state
/// transitions, so no dynamic `.disabled` state tracking is needed here.
struct AppCommands: Commands {

    @FocusedValue(\.editorViewModel) private var editorVM
    @FocusedValue(\.sessionViewModel) private var sessionVM

    var body: some Commands {

        // MARK: File menu — replace "New Window" with "New Script"

        CommandGroup(replacing: .newItem) {
            Button("New Script") {
                editorVM?.createDocument()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        // MARK: Session menu

        CommandMenu("Session") {

            // Start (⌘↩) — guard lets the VM reject if already active
            Button("Start Session") {
                guard let doc = editorVM?.selectedDocument else { return }
                Task { @MainActor in
                    await sessionVM?.start(document: doc)
                }
            }
            .keyboardShortcut(.return, modifiers: .command)

            // Pause (⌘⇧P)
            Button("Pause") {
                sessionVM?.pause()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            // Resume (⌘⇧↩)
            Button("Resume") {
                sessionVM?.resume()
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])

            // Stop (⌘⇧.)
            Button("Stop Session") {
                sessionVM?.stop()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])

            Divider()

            // Reset — returns to idle, closes the teleprompter window
            Button("Reset") {
                sessionVM?.reset()
            }

            Divider()

            // Reveal the recording in Finder (only meaningful after a session)
            Button("Show Recording in Finder") {
                sessionVM?.revealRecordingInFinder()
            }

            Divider()

            // Font-size shortcuts — standard macOS ⌘= / ⌘- for zoom in / out.
            Button("Increase Font Size") {
                guard let vm = sessionVM else { return }
                vm.settings.fontSize = min(72, vm.settings.fontSize + 2)
            }
            .keyboardShortcut("=", modifiers: .command)   // ⌘= (labelled ⌘+ on most keyboards)

            Button("Decrease Font Size") {
                guard let vm = sessionVM else { return }
                vm.settings.fontSize = max(18, vm.settings.fontSize - 2)
            }
            .keyboardShortcut("-", modifiers: .command)   // ⌘-
        }
    }
}
