import CoreGraphics
import Foundation

/// Persisted user preferences that apply to every prompting session.
///
/// Codable so it can be written to / read from a JSON file by `PersistenceService`.
struct SessionSettings: Codable, Equatable {

    // MARK: Display

    /// Point size for the teleprompter text.
    var fontSize: CGFloat = 36

    /// Line-height multiplier applied to the teleprompter view.
    var lineSpacing: CGFloat = 1.4

    // MARK: Window behaviour

    /// When `true`, the teleprompter window floats above all other windows.
    var alwaysOnTop: Bool = true

    /// When `true`, the teleprompter text is horizontally mirrored for use
    /// with reflective teleprompter hardware.
    var mirrorMode: Bool = false

    // MARK: Scroll behaviour

    /// Damping factor (0.0–1.0) applied to scroll animations.
    /// Higher values produce slower, smoother scrolling; lower values are snappier.
    var scrollSmoothing: Double = 0.35

    /// Vertical fraction of the teleprompter window height at which the
    /// current spoken word should be anchored (0.0 = top, 1.0 = bottom).
    /// Default of 0.32 places it near the lower edge of the top third.
    var scrollAnchorFraction: Double = 0.32

    // MARK: Audio input

    /// `uniqueID` of the `AVCaptureDevice` the user has chosen, or `nil` to use
    /// the system's default input.  Stored here so the selection survives app restarts.
    var selectedMicrophoneID: String? = nil

    // MARK: Audio output

    /// Security-scoped bookmark data for the user-chosen recordings folder.
    /// `nil` means use the default path inside Application Support.
    /// Created by `SessionViewModel.selectAudioSaveFolder()` via `NSOpenPanel`.
    var audioSaveFolderBookmark: Data? = nil

    // MARK: Defaults

    static let `default` = SessionSettings()
}

extension SessionSettings {

    /// Resolves `audioSaveFolderBookmark` into a security-scoped URL.
    ///
    /// Returns `nil` if no bookmark is stored or if resolution fails (e.g. the
    /// folder was deleted).  The caller must invoke
    /// `startAccessingSecurityScopedResource()` before any file I/O on this URL.
    var audioSaveFolderURL: URL? {
        guard let data = audioSaveFolderBookmark else { return nil }
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    /// Display name for the save-folder control — last path component, or "Default".
    var audioSaveFolderDisplayName: String {
        audioSaveFolderURL?.lastPathComponent ?? "Default"
    }
}
