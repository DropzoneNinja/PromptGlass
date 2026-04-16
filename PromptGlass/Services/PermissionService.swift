import AVFoundation
import AppKit
import Observation
import Speech

// MARK: - Permission status

/// Unified authorization state for a single system permission.
enum PermissionStatus: Equatable {
    /// The user has not been asked yet.
    case notDetermined
    /// The user (or MDM) has granted access.
    case granted
    /// The user explicitly denied access — app must direct them to System Settings.
    case denied
    /// Access is blocked by parental controls or MDM; the user cannot change it.
    case restricted
}

extension PermissionStatus {
    init(_ avStatus: AVAuthorizationStatus) {
        switch avStatus {
        case .authorized:    self = .granted
        case .denied:        self = .denied
        case .restricted:    self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default:    self = .notDetermined
        }
    }

    init(_ sfStatus: SFSpeechRecognizerAuthorizationStatus) {
        switch sfStatus {
        case .authorized:    self = .granted
        case .denied:        self = .denied
        case .restricted:    self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default:    self = .notDetermined
        }
    }
}

// MARK: - Permission kind

/// Identifies which permission to open in System Settings.
enum PermissionKind {
    case microphone
    case speechRecognition
}

// MARK: - Service

/// Manages microphone and speech-recognition authorization for the app.
///
/// Marked `@MainActor` so that all `@Observable` property mutations are
/// automatically on the main thread, making it safe to bind directly to
/// SwiftUI views and `@Observable` ViewModels.
@MainActor
@Observable
final class PermissionService {

    // MARK: State

    /// Current microphone authorization status.
    private(set) var microphoneStatus: PermissionStatus

    /// Current speech-recognition authorization status.
    private(set) var speechStatus: PermissionStatus

    // MARK: Derived

    /// `true` only when both permissions are granted.
    var allGranted: Bool {
        microphoneStatus == .granted && speechStatus == .granted
    }

    /// `true` when at least one permission is denied or restricted.
    /// Use this to show the "open System Settings" guidance UI.
    var anyDeniedOrRestricted: Bool {
        microphoneStatus == .denied  || microphoneStatus == .restricted ||
        speechStatus == .denied      || speechStatus == .restricted
    }

    // MARK: Init

    init() {
        // Seed from the OS immediately so there is no notDetermined flash
        // on app re-launch if the user already granted permissions.
        microphoneStatus = PermissionStatus(AVCaptureDevice.authorizationStatus(for: .audio))
        speechStatus     = PermissionStatus(SFSpeechRecognizer.authorizationStatus())
    }

    // MARK: Requesting permissions

    /// Requests microphone then speech-recognition authorization in sequence.
    ///
    /// The OS shows its permission dialogs one at a time; sequential requests
    /// ensure the user sees one dialog before the next appears.
    func requestAll() async {
        await requestMicrophone()
        await requestSpeechRecognition()
    }

    private func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneStatus = granted ? .granted : .denied
    }

    private func requestSpeechRecognition() async {
        // SFSpeechRecognizer uses a completion-handler API; bridge to async/await.
        let sfStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        speechStatus = PermissionStatus(sfStatus)
    }

    // MARK: System Settings

    /// Opens System Settings directly to the relevant Privacy pane.
    ///
    /// Call this when `anyDeniedOrRestricted` is true and the user taps a
    /// "Open System Settings" button in the UI.
    func openSystemSettings(for kind: PermissionKind) {
        let urlString: String
        switch kind {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .speechRecognition:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        }
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Convenience overload that opens Settings for whichever permission is
    /// currently denied/restricted, preferring microphone if both are.
    func openSystemSettingsForDeniedPermission() {
        if microphoneStatus == .denied || microphoneStatus == .restricted {
            openSystemSettings(for: .microphone)
        } else if speechStatus == .denied || speechStatus == .restricted {
            openSystemSettings(for: .speechRecognition)
        }
    }
}
