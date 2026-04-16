import SwiftUI

/// Root view of the main editor window.
///
/// Owns all top-level view-model instances and threads them into `MainEditorView`.
/// Also manages the `TeleprompterWindowController` that opens the floating
/// teleprompter window whenever a session starts.
///
/// ## View-model ownership
/// `SessionViewModel` and `TeleprompterViewModel` share the same
/// `SpeechAlignmentEngine` and `AudioMeterProcessor` instances, so they must
/// be created together in `init()` rather than separately as default-value
/// expressions.
struct ContentView: View {

    // MARK: - View models

    @State private var editorVM:       ScriptEditorViewModel
    @State private var sessionVM:      SessionViewModel
    @State private var teleprompterVM: TeleprompterViewModel
    @State private var permissionService = PermissionService()

    // MARK: - Window management

    @State private var windowController = TeleprompterWindowController()

    // MARK: - Init

    init() {
        let settings = PersistenceService.shared.loadSettings()
        let session  = SessionViewModel(settings: settings)
        let teleprompter = TeleprompterViewModel(
            alignmentEngine: session.alignmentEngine,
            audioMeter:      session.audioMeter
        )
        _editorVM       = State(initialValue: ScriptEditorViewModel())
        _sessionVM      = State(initialValue: session)
        _teleprompterVM = State(initialValue: teleprompter)
    }

    // MARK: - Body

    var body: some View {
        MainEditorView(
            editorVM:          editorVM,
            sessionVM:         sessionVM,
            permissionService: permissionService
        )
        .frame(minWidth: 800, minHeight: 560)
        // Expose view models to menu-bar Commands via AppCommands.
        .focusedSceneValue(\.editorViewModel, editorVM)
        .focusedSceneValue(\.sessionViewModel, sessionVM)
        // Open the teleprompter window when a session becomes active;
        // close it when the session stops completely.
        .onChange(of: sessionVM.isActive) { _, isActive in
            if isActive {
                // Load the current script's tokens into the teleprompter view model.
                let tokens = editorVM.selectedDocument?.tokens ?? []
                teleprompterVM.loadTokens(tokens)
                teleprompterVM.applySettings(sessionVM.settings)
                windowController.open(
                    teleprompterVM: teleprompterVM,
                    sessionVM:      sessionVM
                )
            } else {
                teleprompterVM.resetScrollState()
                windowController.close()
            }
        }
        // Propagate settings changes (font, spacing, mirror) to the scroll coordinator.
        .onChange(of: sessionVM.settings) { _, newSettings in
            teleprompterVM.applySettings(newSettings)
        }
    }
}
