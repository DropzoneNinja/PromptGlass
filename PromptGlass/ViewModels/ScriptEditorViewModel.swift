import Foundation
import Observation

/// Manages the script document list and the currently selected/edited script.
///
/// ## Responsibilities
/// - Load and persist `ScriptDocument` values via `PersistenceService`.
/// - Expose a mutable `selectedDocument` for the editor view to bind to.
/// - Track unsaved changes (`isDirty`) so the UI can show a save indicator.
/// - Parse the selected document whenever its raw text changes, keeping
///   `selectedDocument.tokens` up to date for the teleprompter.
///
/// ## Threading
/// All mutations happen on the `@MainActor`; `PersistenceService` I/O is
/// synchronous and fast enough to stay on the main thread.
@MainActor
@Observable
final class ScriptEditorViewModel {

    // MARK: - Observable state

    /// All saved scripts, sorted by most-recently-modified first.
    private(set) var documents: [ScriptDocument] = []

    /// The script currently open in the editor. `nil` means no script is selected.
    var selectedDocument: ScriptDocument? {
        didSet { onSelectedDocumentChanged(oldValue: oldValue) }
    }

    /// `true` when `selectedDocument` has unsaved changes.
    private(set) var isDirty: Bool = false

    /// Non-nil when the last save attempt failed.
    private(set) var saveError: Error?

    /// Set to `true` to trigger the import-from-file panel in the owning view.
    /// The view resets this to `false` after handling it.
    var showImportPanel: Bool = false

    /// User-readable description of `saveError`; `nil` when there is no error.
    ///
    /// `Error` is not `Equatable`, so views should observe this `String?` property
    /// (which is `Equatable`) to drive alert presentation via `onChange(of:)`.
    var saveErrorMessage: String? { saveError?.localizedDescription }

    // MARK: - Convenience accessors

    /// The parsed tokens of the currently selected document; empty if none selected.
    var parsedTokens: [ScriptToken] {
        selectedDocument?.tokens ?? []
    }

    /// The spoken tokens of the currently selected document; used by the
    /// alignment engine when loading a new session.
    var spokenTokens: [SpokenToken] {
        selectedDocument?.spokenTokens ?? []
    }

    // MARK: - Dependencies

    private let persistence: PersistenceService

    // MARK: - Init

    init(persistence: PersistenceService = .shared) {
        self.persistence = persistence
    }

    // MARK: - Lifecycle

    /// Load documents from disk and restore the last-opened selection.
    ///
    /// Call once from the app's root view `.onAppear`.
    func loadDocuments() {
        var loaded = persistence.loadDocuments()

        // Re-parse each document so tokens are populated in memory.
        for index in loaded.indices {
            ScriptParser.parse(&loaded[index])
        }

        documents = loaded.sorted { $0.modifiedAt > $1.modifiedAt }

        // Restore last-opened selection.
        if let lastID = persistence.loadLastOpenedID(),
           let match = documents.first(where: { $0.id == lastID }) {
            selectedDocument = match
        } else {
            selectedDocument = documents.first
        }
        isDirty = false
    }

    // MARK: - CRUD

    /// Creates a new blank script, selects it, and persists the updated list.
    @discardableResult
    func createDocument(name: String = "Untitled") -> ScriptDocument {
        var doc = ScriptDocument(name: name)
        ScriptParser.parse(&doc)
        documents.insert(doc, at: 0)
        selectedDocument = doc
        isDirty = false
        trySave()
        return doc
    }

    /// Creates a new script pre-populated with `text`, selects it, and persists.
    @discardableResult
    func importDocument(name: String, text: String) -> ScriptDocument {
        var doc = ScriptDocument(name: name, rawText: text)
        ScriptParser.parse(&doc)
        documents.insert(doc, at: 0)
        selectedDocument = doc
        isDirty = false
        trySave()
        return doc
    }

    /// Rename the given document.
    ///
    /// If the document is currently selected its in-memory copy is updated too.
    func renameDocument(_ document: ScriptDocument, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        updateDocument(document) { $0.name = trimmed }
        trySave()
    }

    /// Delete the given document.
    ///
    /// If it was selected, the selection moves to the next available document.
    func deleteDocument(_ document: ScriptDocument) {
        let wasSelected = selectedDocument?.id == document.id
        documents.removeAll { $0.id == document.id }

        if wasSelected {
            selectedDocument = documents.first
            isDirty = false
        }
        trySave()
    }

    /// Persist all in-memory changes to disk.
    ///
    /// Errors are surfaced through `saveError`; they do not throw so callers
    /// don't need to handle them (the UI should observe `saveError` instead).
    func saveCurrentDocument() {
        guard isDirty else { return }
        guard let doc = selectedDocument else { return }

        // ScriptDocument is a value type: selectedDocument and documents[idx] are
        // independent copies.  Copy every field from the edited copy into the array.
        updateDocument(doc) { $0 = doc }
        trySave()
        isDirty = false
    }

    // MARK: - Editor binding support

    /// Called by the editor view when the user types.
    ///
    /// Updates `selectedDocument.rawText`, re-parses tokens immediately so
    /// the teleprompter preview stays current, flushes the change back to the
    /// `documents` array, and auto-saves to disk.  Auto-saving here means text
    /// is never silently lost when the app quits without an explicit Cmd+S.
    func updateText(_ newText: String) {
        guard selectedDocument?.rawText != newText else { return }
        selectedDocument?.rawText = newText
        if var doc = selectedDocument {
            ScriptParser.parse(&doc)
            selectedDocument = doc
        }
        isDirty = true

        // Flush the edited copy back into the documents array so trySave()
        // writes the current text.  ScriptDocument is a value type, so
        // selectedDocument and documents[idx] are independent copies.
        guard let doc = selectedDocument,
              let idx = documents.firstIndex(where: { $0.id == doc.id })
        else { return }
        documents[idx] = doc
        documents[idx].modifiedAt = Date()
        trySave()
    }

    // MARK: - Private helpers

    /// Responds to `selectedDocument` being replaced (via the `didSet` observer).
    ///
    /// Records the new selection in `UserDefaults` for next-launch restoration
    /// and resets dirty state (the editor is now showing a freshly-selected doc).
    private func onSelectedDocumentChanged(oldValue: ScriptDocument?) {
        guard selectedDocument?.id != oldValue?.id else { return }
        persistence.saveLastOpenedID(selectedDocument?.id)
        isDirty = false
    }

    /// Applies `mutation` to the copy of `document` held in the `documents` array
    /// and, if it is currently selected, to `selectedDocument` as well.
    private func updateDocument(_ document: ScriptDocument, mutation: (inout ScriptDocument) -> Void) {
        guard let idx = documents.firstIndex(where: { $0.id == document.id }) else { return }
        mutation(&documents[idx])
        documents[idx].modifiedAt = Date()

        if selectedDocument?.id == document.id {
            selectedDocument = documents[idx]
        }
    }

    /// Sorts `documents` by most-recently-modified, persists to disk, and
    /// records any error in `saveError`.
    private func trySave() {
        documents.sort { $0.modifiedAt > $1.modifiedAt }
        do {
            try persistence.saveDocuments(documents)
            saveError = nil
        } catch {
            saveError = error
        }
    }
}
