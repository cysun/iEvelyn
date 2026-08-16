import SwiftUI
import UniformTypeIdentifiers

struct MarkdownChapterEditorView: View {
    @State private var model: ChapterEditorViewModel
    let previewModel: ChapterPreviewViewModel
    let chapter: Chapter
    let isReadOnly: Bool

    @Environment(\.undoManager) private var undoManager
    @State private var selection: TextSelection?
    @State private var isFindPresented = false
    @State private var isImporterPresented = false
    @State private var conflictResolution: ConflictResolution?

    init(
        model: ChapterEditorViewModel,
        previewModel: ChapterPreviewViewModel,
        chapter: Chapter,
        isReadOnly: Bool
    ) {
        _model = State(initialValue: model)
        self.previewModel = previewModel
        self.chapter = chapter
        self.isReadOnly = isReadOnly
    }

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Markdown", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.headline)

                saveStatus
                    .accessibilityIdentifier("chapter-editor-save-status")

                Spacer()

                Button("Find", systemImage: "magnifyingglass") {
                    isFindPresented = true
                }
                .help("Find and replace in this chapter")
                .keyboardShortcut("f", modifiers: .command)
                .accessibilityIdentifier("chapter-editor-find")

                if !isReadOnly {
                    Button("Import…", systemImage: "square.and.arrow.down") {
                        isImporterPresented = true
                    }
                    .help("Replace this draft with a UTF-8 Markdown or text file")
                    .disabled(model.isImporting)
                    .accessibilityIdentifier("chapter-editor-import")
                }
            }

            HSplitView {
                editorPane
                    .frame(minWidth: 280, idealWidth: 360)

                MarkdownLivePreviewView(
                    model: previewModel,
                    chapter: chapter,
                    markdown: model.markdown,
                    generation: model.previewGeneration
                )
                    .frame(minWidth: 220, idealWidth: 300)
            }
            .frame(minHeight: 360, idealHeight: 440)

            HStack(spacing: 14) {
                Text(wordDescription(model.metrics.wordCount))
                    .accessibilityIdentifier("chapter-editor-word-count")
                Text(characterDescription(model.metrics.characterCount))
                    .accessibilityIdentifier("chapter-editor-character-count")
                Spacer()
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            if let importErrorMessage = model.importErrorMessage {
                errorBanner(
                    title: "Could Not Import Chapter",
                    message: importErrorMessage
                ) {
                    Button("Choose Another File…") {
                        isImporterPresented = true
                    }
                }
            }

            saveRecoveryBanner
        }
        .task(id: chapter.id) {
            if await model.activate(chapter) {
                selection = nil
            }
        }
        .onChange(of: chapter) { _, observedChapter in
            model.receiveObservedChapter(observedChapter)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: chapterImportTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let sourceURL = urls.first else { return }
                Task {
                    await model.importChapterSource(from: sourceURL, undoManager: undoManager)
                }
            case .failure(let error):
                guard (error as NSError).code != NSUserCancelledError else { return }
                model.reportImportFailure(error)
            }
        }
        .confirmationDialog(
            conflictResolution?.title ?? "Resolve Editing Conflict",
            isPresented: Binding(
                get: { conflictResolution != nil },
                set: { if !$0 { conflictResolution = nil } }
            ),
            titleVisibility: .visible,
            presenting: conflictResolution
        ) { resolution in
            switch resolution {
            case .reload:
                Button("Reload Stored Version", role: .destructive) {
                    conflictResolution = nil
                    model.reloadStoredVersion()
                }
            case .overwrite:
                Button("Overwrite Stored Version", role: .destructive) {
                    conflictResolution = nil
                    Task { await model.overwriteStoredVersion() }
                }
            }
            Button("Cancel", role: .cancel) {
                conflictResolution = nil
            }
        } message: { resolution in
            Text(resolution.message)
        }
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Source")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextEditor(
                text: Binding(
                    get: { model.markdown },
                    set: { model.updateMarkdown($0) }
                ),
                selection: $selection
            )
            .font(.system(.body, design: .monospaced))
            .textEditorStyle(.plain)
            .findNavigator(isPresented: $isFindPresented)
            .findDisabled(false)
            .replaceDisabled(isReadOnly)
            .disabled(isReadOnly || model.activeChapterID != chapter.id)
            .padding(8)
            .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.secondary.opacity(0.25))
            }
            .accessibilityLabel("Markdown source for \(chapter.title)")
            .accessibilityIdentifier("chapter-markdown-editor")
        }
        .padding(.trailing, 6)
    }

    @ViewBuilder
    private var saveStatus: some View {
        if isReadOnly {
            Label("Read Only", systemImage: "lock")
                .foregroundStyle(.secondary)
        } else {
            switch model.saveState {
            case .saved:
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .waiting:
                Label("Waiting to Save", systemImage: "clock")
                    .foregroundStyle(.secondary)
            case .saving:
                Label("Saving…", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    .foregroundStyle(.secondary)
            case .failed:
                Label("Not Saved", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            case .conflict:
                Label("Editing Conflict", systemImage: "arrow.triangle.branch")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var saveRecoveryBanner: some View {
        switch model.saveState {
        case .failed(let message):
            errorBanner(title: "Chapter Was Not Saved", message: message) {
                Button("Retry") {
                    Task { await model.retrySave() }
                }
                .accessibilityIdentifier("chapter-editor-retry-save")

                Button("Revert Draft", role: .destructive) {
                    model.discardUnsavedChanges()
                }
            }

        case .conflict(let message):
            errorBanner(title: "Editing Conflict", message: message) {
                Button("Reload Stored…") {
                    conflictResolution = .reload
                }
                .accessibilityIdentifier("chapter-editor-reload-conflict")

                Button("Overwrite Stored…", role: .destructive) {
                    conflictResolution = .overwrite
                }
                .accessibilityIdentifier("chapter-editor-overwrite-conflict")
            }

        default:
            EmptyView()
        }
    }

    private func errorBanner<Actions: View>(
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                actions()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func wordDescription(_ count: Int) -> String {
        count == 1 ? "1 word" : "\(count) words"
    }

    private func characterDescription(_ count: Int) -> String {
        count == 1 ? "1 character" : "\(count) characters"
    }

    private var chapterImportTypes: [UTType] {
        if let markdownType = UTType(filenameExtension: "md") {
            [markdownType, .plainText]
        } else {
            [.plainText]
        }
    }
}

private enum ConflictResolution: Hashable, Identifiable {
    case reload
    case overwrite

    var id: Self { self }

    var title: String {
        switch self {
        case .reload:
            "Discard This Draft?"
        case .overwrite:
            "Overwrite the Stored Chapter?"
        }
    }

    var message: String {
        switch self {
        case .reload:
            "The unsaved draft in this window will be replaced by the version saved from another window."
        case .overwrite:
            "The version saved from another window will be replaced by this draft."
        }
    }
}
