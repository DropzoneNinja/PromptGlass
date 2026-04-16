import AVFoundation
import SwiftUI

/// Bottom-panel inspector showing session settings and session-lifecycle controls.
///
/// ## Layout
/// ```
/// [Font stepper] | [Spacing slider] | [Mirror] | [Mic picker]      [Start/Pause/Stop]
/// ```
///
/// Settings changes write directly to `sessionVM.settings`, which auto-saves
/// to disk via `SessionViewModel.applySettingsToServices()`.
struct SessionControlsView: View {

    var sessionVM: SessionViewModel
    var editorVM: ScriptEditorViewModel
    var permissionService: PermissionService

    /// Audio input devices found on the current system.
    @State private var availableMicrophones: [AVCaptureDevice] = []
    @State private var showSessionErrorAlert = false

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            fontSizeControl
            controlDivider
            lineSpacingControl
            controlDivider
            mirrorToggle
            if !availableMicrophones.isEmpty {
                controlDivider
                microphonePicker
            }
            controlDivider
            audioSaveFolderPicker
            Spacer(minLength: 12)
            sessionControls
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        // Reload device list when mic permission is granted after the view appears.
        .onChange(of: permissionService.microphoneStatus) { _, status in
            if status == .granted { loadMicrophones() }
        }
        .onAppear { loadMicrophones() }
        .alert("Session Error", isPresented: $showSessionErrorAlert) {
            Button("OK") { }
        } message: {
            Text(sessionVM.sessionError ?? "")
        }
        .onChange(of: sessionVM.sessionError) { _, newError in
            if newError != nil { showSessionErrorAlert = true }
        }
    }

    // MARK: - Font size

    private var fontSizeControl: some View {
        HStack(spacing: 6) {
            Text("Font")
                .font(.caption)
                .foregroundStyle(.secondary)
            Stepper(
                "\(Int(sessionVM.settings.fontSize)) pt",
                value: Binding(
                    get: { sessionVM.settings.fontSize },
                    set: { sessionVM.settings.fontSize = $0 }
                ),
                in: 18...72,
                step: 2
            )
            .fixedSize()
        }
    }

    // MARK: - Line spacing

    private var lineSpacingControl: some View {
        HStack(spacing: 6) {
            Text("Spacing")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { sessionVM.settings.lineSpacing },
                    set: { sessionVM.settings.lineSpacing = $0 }
                ),
                in: 1.0...2.5,
                step: 0.1
            )
            .frame(width: 80)
            Text(String(format: "%.1f×", sessionVM.settings.lineSpacing))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 30, alignment: .leading)
        }
    }

    // MARK: - Mirror toggle

    private var mirrorToggle: some View {
        Toggle(
            "Mirror",
            isOn: Binding(
                get: { sessionVM.settings.mirrorMode },
                set: { sessionVM.settings.mirrorMode = $0 }
            )
        )
        .toggleStyle(.checkbox)
    }

    // MARK: - Audio save folder

    private var audioSaveFolderPicker: some View {
        HStack(spacing: 6) {
            Text("Save to")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(action: { sessionVM.selectAudioSaveFolder() }) {
                Label(sessionVM.settings.audioSaveFolderDisplayName, systemImage: "folder")
                    .lineLimit(1)
            }
            .frame(maxWidth: 140)
            .help("Choose a folder for audio recordings")
            .contextMenu {
                Button("Reset to Default Folder") {
                    sessionVM.clearAudioSaveFolder()
                }
                .disabled(sessionVM.settings.audioSaveFolderBookmark == nil)
            }
        }
        .disabled(sessionVM.isActive)
    }

    // MARK: - Microphone picker

    private var microphonePicker: some View {
        HStack(spacing: 6) {
            Text("Mic")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { sessionVM.settings.selectedMicrophoneID },
                set: { sessionVM.settings.selectedMicrophoneID = $0 }
            )) {
                Text("System Default").tag(Optional<String>.none)
                ForEach(availableMicrophones, id: \.uniqueID) { device in
                    Text(device.localizedName).tag(Optional(device.uniqueID))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 160)
            // Show which device is actually recording once a session is running.
            if sessionVM.isActive {
                Text("(\(sessionVM.activeInputDeviceName))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Session controls

    @ViewBuilder
    private var sessionControls: some View {
        switch sessionVM.session.state {

        case .idle, .stopped:
            Button(action: startSession) {
                Label("Start Session", systemImage: "play.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canStartSession)
            .help(startButtonHelp)

        case .running:
            HStack(spacing: 8) {
                Button(action: { sessionVM.pause() }) {
                    Label("Pause", systemImage: "pause.circle.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Button(action: { sessionVM.stop() }) {
                    Label("Stop", systemImage: "stop.circle.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.large)
            }

        case .paused:
            HStack(spacing: 8) {
                Button(action: { sessionVM.resume() }) {
                    Label("Resume", systemImage: "play.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button(action: { sessionVM.stop() }) {
                    Label("Stop", systemImage: "stop.circle.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Helpers

    private var canStartSession: Bool {
        editorVM.selectedDocument != nil && permissionService.allGranted
    }

    private var startButtonHelp: String {
        if editorVM.selectedDocument == nil {
            return "Select or create a script to begin."
        }
        if !permissionService.allGranted {
            return "Microphone and speech recognition permissions are required."
        }
        return "Begin a prompting session for this script."
    }

    private func startSession() {
        guard let doc = editorVM.selectedDocument else { return }
        Task { await sessionVM.start(document: doc) }
    }

    private func loadMicrophones() {
        availableMicrophones = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    private var controlDivider: some View {
        Divider().frame(height: 20)
    }
}
