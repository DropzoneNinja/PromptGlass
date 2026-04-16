import Foundation

/// Reads and writes app data to the user's Application Support directory.
///
/// All methods are synchronous and safe to call on the main thread — scripts
/// and settings files are small enough that disk I/O is not a bottleneck.
///
/// ## File layout
/// ```
/// ~/Library/Application Support/PromptGlass/
///     documents.json   — array of ScriptDocument (raw text + metadata only)
///     settings.json    — SessionSettings
/// ```
/// The last-opened document ID is stored in `UserDefaults` because it is a
/// single transient value that needs no migration strategy.
final class PersistenceService {

    // MARK: - Shared instance

    static let shared = PersistenceService()

    // MARK: - URLs

    private let documentsFileURL: URL
    private let settingsFileURL: URL
    private let lastOpenedDefaultsKey = "PromptGlass.lastOpenedDocumentID"

    // MARK: - Init

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PromptGlass", isDirectory: true)

        // Create the directory on first launch; harmless if it already exists.
        try? FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )

        documentsFileURL = appSupport.appendingPathComponent("documents.json")
        settingsFileURL  = appSupport.appendingPathComponent("settings.json")
    }

    // MARK: - Documents

    /// Persists the full document list atomically.
    ///
    /// Only `rawText` and metadata are encoded — parsed `tokens` are
    /// intentionally excluded by `ScriptDocument`'s `CodingKeys`.
    /// - Throws: `EncodingError` or a file-system error on failure.
    func saveDocuments(_ documents: [ScriptDocument]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(documents)
        try data.write(to: documentsFileURL, options: .atomic)
    }

    /// Loads the document list from disk.
    ///
    /// Returns an empty array if the file does not yet exist.
    /// Returns an empty array and silently discards any decoding error
    /// (e.g. schema mismatch, truncation) so the app always starts clean.
    func loadDocuments() -> [ScriptDocument] {
        guard FileManager.default.fileExists(atPath: documentsFileURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: documentsFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ScriptDocument].self, from: data)
        } catch {
            // Corrupted file — start fresh rather than blocking the user.
            return []
        }
    }

    // MARK: - Settings

    /// Persists `SessionSettings` atomically.
    /// - Throws: `EncodingError` or a file-system error on failure.
    func saveSettings(_ settings: SessionSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: settingsFileURL, options: .atomic)
    }

    /// Loads `SessionSettings` from disk.
    ///
    /// Returns `SessionSettings.default` if the file does not exist or
    /// cannot be decoded (e.g. after an app update adds new fields).
    func loadSettings() -> SessionSettings {
        guard FileManager.default.fileExists(atPath: settingsFileURL.path) else {
            return .default
        }
        do {
            let data = try Data(contentsOf: settingsFileURL)
            return try JSONDecoder().decode(SessionSettings.self, from: data)
        } catch {
            return .default
        }
    }

    // MARK: - Last-opened document

    /// Records the ID of the most recently opened script.
    /// Pass `nil` to clear the stored value.
    func saveLastOpenedID(_ id: UUID?) {
        UserDefaults.standard.set(id?.uuidString, forKey: lastOpenedDefaultsKey)
    }

    /// Returns the UUID of the most recently opened script, or `nil` if none
    /// has been recorded or the stored string is not a valid UUID.
    func loadLastOpenedID() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: lastOpenedDefaultsKey) else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    // MARK: - Diagnostics

    /// File-system URLs exposed for debugging / unit testing.
    var documentsURL: URL { documentsFileURL }
    var settingsURL:  URL { settingsFileURL  }
}
