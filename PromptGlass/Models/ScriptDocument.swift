import Foundation

/// A user-created script that can be edited, saved, and loaded into a prompting session.
///
/// `rawText` is the source of truth and the only field that is persisted.
/// `tokens` is populated by `ScriptParser` each time the document is parsed;
/// it is intentionally excluded from `Codable` encoding.
struct ScriptDocument: Identifiable, Codable {
    var id: UUID
    var name: String
    var rawText: String
    var createdAt: Date
    var modifiedAt: Date

    // Derived by ScriptParser — not stored on disk.
    var tokens: [ScriptToken] = []

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, rawText, createdAt, modifiedAt
    }

    // MARK: Init

    init(id: UUID = UUID(), name: String = "Untitled", rawText: String = "") {
        self.id = id
        self.name = name
        self.rawText = rawText
        let now = Date()
        self.createdAt = now
        self.modifiedAt = now
    }

    // MARK: Helpers

    /// Convenience accessor for only the spoken tokens in order.
    var spokenTokens: [SpokenToken] {
        tokens.compactMap {
            if case .spoken(let t) = $0 { return t }
            return nil
        }
    }
}
