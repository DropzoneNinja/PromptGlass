import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Root view for the main editor window.
///
/// ## Layout
/// ```
/// ┌──────────────┬─────────────────────────────────┐
/// │  Scripts     │  Document title            [Save]│ ← toolbar
/// │  ──────────  │  ─────────────────────────────── │
/// │  Script 1  ● │  <TextEditor>                    │
/// │  Script 2    │                                  │
/// │  Script 3    │  ─────────────────────────────── │
/// │              │  [Font] [Spacing] [Mirror] [Start]│
/// └──────────────┴─────────────────────────────────┘
/// ```
///
/// The sidebar lists all saved scripts; the detail area contains the
/// `ScriptEditorView` on top and `SessionControlsView` pinned to the bottom.
struct MainEditorView: View {

    var editorVM: ScriptEditorViewModel
    var sessionVM: SessionViewModel
    var permissionService: PermissionService

    // MARK: - Local dialog state

    @State private var showRenameAlert    = false
    @State private var showDeleteDialog   = false
    @State private var showSaveErrorAlert = false
    @State private var documentToRename:   ScriptDocument?
    @State private var documentToDelete:   ScriptDocument?
    @State private var renameText = ""
    @State private var showFileError      = false
    @State private var fileErrorMessage   = ""

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Permission warning banners sit above the split view so they are
            // always visible regardless of which document (if any) is selected.
            if permissionService.anyDeniedOrRestricted {
                permissionBanners
            }

            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 160, ideal: 200)
            } detail: {
                detail
            }
        }
        // Load documents and request permissions on first appearance.
        .task {
            editorVM.loadDocuments()
            if !permissionService.allGranted {
                await permissionService.requestAll()
            }
        }
        // Rename alert
        .alert("Rename Script", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let doc = documentToRename {
                    editorVM.renameDocument(doc, to: renameText)
                }
                documentToRename = nil
            }
            .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {
                documentToRename = nil
            }
        }
        // Delete confirmation
        .confirmationDialog(
            "Delete \"\(documentToDelete?.name ?? "")\"?",
            isPresented: $showDeleteDialog,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let doc = documentToDelete {
                    editorVM.deleteDocument(doc)
                }
                documentToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                documentToDelete = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
        // Save error alert
        .alert("Could Not Save Script", isPresented: $showSaveErrorAlert) {
            Button("OK") { }
        } message: {
            Text(editorVM.saveErrorMessage ?? "An unknown error occurred while saving.")
        }
        .onChange(of: editorVM.saveErrorMessage) { _, message in
            if message != nil { showSaveErrorAlert = true }
        }
        // File import/export error alert
        .alert("File Error", isPresented: $showFileError) {
            Button("OK") { }
        } message: {
            Text(fileErrorMessage)
        }
        // Triggered by the File menu "Import Script…" command via AppCommands.
        .onChange(of: editorVM.showImportPanel) { _, show in
            if show {
                editorVM.showImportPanel = false
                importFromFile()
            }
        }
    }

    // MARK: - Permission banners

    /// Stacked warning rows, one per denied/restricted permission.
    @ViewBuilder
    private var permissionBanners: some View {
        if permissionService.microphoneStatus == .denied
            || permissionService.microphoneStatus == .restricted {
            PermissionBannerRow(
                icon: "mic.slash.fill",
                message: permissionService.microphoneStatus == .restricted
                    ? "Microphone access is restricted by a system policy and cannot be changed here."
                    : "Microphone access is denied. PromptGlass needs it to follow your speech.",
                canOpenSettings: permissionService.microphoneStatus == .denied
            ) {
                permissionService.openSystemSettings(for: .microphone)
            }
        }
        if permissionService.speechStatus == .denied
            || permissionService.speechStatus == .restricted {
            PermissionBannerRow(
                icon: "waveform.badge.exclamationmark",
                message: permissionService.speechStatus == .restricted
                    ? "Speech Recognition is restricted by a system policy and cannot be changed here."
                    : "Speech Recognition is denied. Enable it so PromptGlass can track spoken words.",
                canOpenSettings: permissionService.speechStatus == .denied
            ) {
                permissionService.openSystemSettings(for: .speechRecognition)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: selectionBinding) {
            ForEach(editorVM.documents) { doc in
                scriptRow(doc)
                    .tag(doc.id)
                    .onLongPressGesture(minimumDuration: 0.5) { beginRename(doc) }
                    .contextMenu {
                        Button("Rename…") { beginRename(doc) }
                        Divider()
                        Button("Save as Text File…") { exportAsText(doc) }
                        Divider()
                        Button("Delete", role: .destructive) { beginDelete(doc) }
                    }
            }
        }
        .navigationTitle("Scripts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Script") { editorVM.createDocument() }
                    Button("Import from File…") { importFromFile() }
                } label: {
                    Label("New Script", systemImage: "plus")
                }
                .help("New Script or Import")
            }
        }
    }

    /// One row in the script list: document name with optional dirty dot, plus
    /// a relative-date subtitle.
    @ViewBuilder
    private func scriptRow(_ doc: ScriptDocument) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(doc.name)
                    .font(.body)
                    .lineLimit(1)
                // Unsaved-changes indicator — only on the currently selected doc.
                if editorVM.isDirty, editorVM.selectedDocument?.id == doc.id {
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 6, height: 6)
                }
            }
            Text(relativeDate(doc.modifiedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if editorVM.selectedDocument != nil {
            VStack(spacing: 0) {
                ScriptEditorView(editorVM: editorVM)
                    // Prevent editing the script while a session is in progress.
                    .disabled(sessionVM.isActive)
                Divider()
                SessionControlsView(
                    sessionVM: sessionVM,
                    editorVM: editorVM,
                    permissionService: permissionService
                )
            }
            .navigationTitle(detailTitle)
            .toolbar { detailToolbar }
        } else {
            emptyState
                .toolbar { detailToolbar }
        }
    }

    /// Window title: document name with a bullet when there are unsaved changes.
    private var detailTitle: String {
        guard let doc = editorVM.selectedDocument else { return "PromptGlass" }
        return editorVM.isDirty ? "\(doc.name) •" : doc.name
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("No Script Selected")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Create a new script or select one from the sidebar.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("New Script") { editorVM.createDocument() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar (detail column)

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        // Delete — only when a script is selected and no session is running.
        if let doc = editorVM.selectedDocument, !sessionVM.isActive {
            ToolbarItem {
                Button(action: { beginDelete(doc) }) {
                    Label("Delete Script", systemImage: "trash")
                }
                .help("Delete this script")
            }
        }
        // Export as text file — only when a script is selected and no session is running.
        if let doc = editorVM.selectedDocument, !sessionVM.isActive {
            ToolbarItem {
                Button(action: { exportAsText(doc) }) {
                    Label("Save as Text File", systemImage: "square.and.arrow.up")
                }
                .help("Save script as a .txt file")
            }
        }
        // Save — only when there are unsaved changes.
        if editorVM.isDirty {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { editorVM.saveCurrentDocument() }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .help("Save  ⌘S")
            }
        }
    }

    // MARK: - Helpers

    /// Two-way binding that syncs the `List` selection with `editorVM.selectedDocument`.
    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { editorVM.selectedDocument?.id },
            set: { id in
                guard let id,
                      let doc = editorVM.documents.first(where: { $0.id == id })
                else { return }
                editorVM.selectedDocument = doc
            }
        )
    }

    private func beginRename(_ doc: ScriptDocument) {
        documentToRename = doc
        renameText = doc.name
        showRenameAlert = true
    }

    private func beginDelete(_ doc: ScriptDocument) {
        documentToDelete = doc
        showDeleteDialog = true
    }

    private func exportAsText(_ doc: ScriptDocument) {
        let panel = NSSavePanel()
        panel.title = "Save Script as Text File"
        panel.nameFieldStringValue = doc.name + ".txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try doc.rawText.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            fileErrorMessage = error.localizedDescription
            showFileError = true
        }
    }

    func importFromFile() {
        let panel = NSOpenPanel()
        panel.title = "Import Script from Text File"
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let name = url.deletingPathExtension().lastPathComponent
            editorVM.importDocument(name: name, text: text)
        } catch {
            fileErrorMessage = error.localizedDescription
            showFileError = true
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Permission banner row

/// A single-line warning bar shown when a permission is denied or restricted.
///
/// Displayed in a `VStack` above the main `NavigationSplitView` so it is
/// always visible regardless of which detail view is active.
private struct PermissionBannerRow: View {

    let icon: String
    let message: String
    /// `false` when the permission is restricted by policy; the "Open Settings"
    /// button is hidden because the user cannot change restricted permissions.
    let canOpenSettings: Bool
    let onOpenSettings: () -> Void

    init(
        icon: String,
        message: String,
        canOpenSettings: Bool,
        onOpenSettings: @escaping () -> Void
    ) {
        self.icon            = icon
        self.message         = message
        self.canOpenSettings = canOpenSettings
        self.onOpenSettings  = onOpenSettings
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
                .imageScale(.medium)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if canOpenSettings {
                Button("Open Settings", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
