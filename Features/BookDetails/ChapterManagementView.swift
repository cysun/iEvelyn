import SwiftUI

struct ChapterManagementView: View {
    @State private var model: ChapterManagementViewModel
    @State private var editorModel: ChapterEditorViewModel
    let isReadOnly: Bool

    @State private var titleEditor: ChapterTitleEditorConfiguration?
    @State private var deletionCandidate: Chapter?

    init(
        model: ChapterManagementViewModel,
        editorModel: ChapterEditorViewModel,
        isReadOnly: Bool
    ) {
        _model = State(initialValue: model)
        _editorModel = State(initialValue: editorModel)
        self.isReadOnly = isReadOnly
    }

    var body: some View {
        @Bindable var model = model

        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(summaryDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("chapter-summary")

                    Spacer()

                    if !isReadOnly {
                        Button("Add Chapter", systemImage: "plus") {
                            titleEditor = .adding()
                        }
                        .help("Add a chapter")
                        .disabled(model.isPerformingOperation)
                        .accessibilityIdentifier("chapter-add")
                    }
                }

                if isReadOnly {
                    Label(
                        "Restore this book before changing its chapters.",
                        systemImage: "lock"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                if model.isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading chapters…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .accessibilityIdentifier("chapters-loading")
                } else if let errorMessage = model.errorMessage {
                    ContentUnavailableView {
                        Label("Could Not Load Chapters", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try Again") {
                            Task { await model.observeChapters() }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .accessibilityIdentifier("chapters-error")
                } else if model.chapters.isEmpty {
                    emptyState
                } else {
                    chapterRows

                    if let selectedChapter = model.selectedChapter {
                        Divider()
                        selectedChapterActions(selectedChapter)
                    }
                }

                if let deletion = model.deletionToUndo {
                    deletionUndoBanner(deletion)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } label: {
            Text("Chapters")
        }
        .accessibilityIdentifier("chapter-management")
        .task {
            await model.observeChapters()
        }
        .sheet(item: $titleEditor) { configuration in
            ChapterTitleEditorSheet(
                configuration: configuration,
                onCancel: {
                    titleEditor = nil
                },
                onSave: { title in
                    titleEditor = nil
                    Task {
                        guard await editorModel.flushPendingSave() else { return }
                        switch configuration.mode {
                        case .add:
                            await model.createChapter(title: title)
                        case .rename:
                            await model.renameSelectedChapter(to: title)
                        }
                    }
                }
            )
        }
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Chapters", systemImage: "text.page")
        } description: {
            Text("Add the first chapter to begin organizing this book.")
        } actions: {
            if !isReadOnly {
                Button("Add Chapter") {
                    titleEditor = .adding()
                }
                .accessibilityIdentifier("chapter-empty-add")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170)
    }

    private var chapterRows: some View {
        VStack(spacing: 4) {
            ForEach(Array(model.chapters.enumerated()), id: \.element.id) { index, chapter in
                chapterRow(chapter, number: index + 1)
            }
        }
    }

    @ViewBuilder
    private func chapterRow(_ chapter: Chapter, number: Int) -> some View {
        let row = Button {
            Task {
                guard await editorModel.activate(chapter) else { return }
                model.select(chapter.id)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)

                Text("\(number)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 20, alignment: .trailing)

                Text(chapter.title)
                    .lineLimit(1)

                Spacer()

                Text(wordDescription(chapter.wordCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(.rect)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        model.selectedChapterID == chapter.id
                            ? Color.accentColor.opacity(0.14)
                            : Color.clear
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        model.selectedChapterID == chapter.id
                            ? Color.accentColor.opacity(0.45)
                            : Color.secondary.opacity(0.12)
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chapter.title)
        .accessibilityValue("Chapter \(number) of \(model.chapters.count), \(wordDescription(chapter.wordCount))")
        .accessibilityIdentifier("chapter-row-\(chapter.id.uuidString.lowercased())")

        if isReadOnly {
            row
        } else {
            row
                .draggable(chapter.id.uuidString.lowercased())
                .dropDestination(for: String.self) { identifiers, _ in
                    guard let identifier = identifiers.first,
                          let draggedChapterID = UUID(uuidString: identifier),
                          draggedChapterID != chapter.id else {
                        return false
                    }
                    Task {
                        await model.moveChapter(draggedChapterID, before: chapter.id)
                    }
                    return true
                }
        }
    }

    private func selectedChapterActions(_ chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.title)
                        .font(.headline)
                    Text(wordDescription(chapter.wordCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !isReadOnly {
                    Button("Move Up", systemImage: "arrow.up") {
                        Task { await model.moveSelectedChapter(by: -1) }
                    }
                    .labelStyle(.iconOnly)
                    .help("Move chapter up")
                    .disabled(!model.canMoveSelectionUp || model.isPerformingOperation)
                    .accessibilityIdentifier("chapter-move-up")

                    Button("Move Down", systemImage: "arrow.down") {
                        Task { await model.moveSelectedChapter(by: 1) }
                    }
                    .labelStyle(.iconOnly)
                    .help("Move chapter down")
                    .disabled(!model.canMoveSelectionDown || model.isPerformingOperation)
                    .accessibilityIdentifier("chapter-move-down")
                }
            }

            MarkdownChapterEditorView(
                model: editorModel,
                chapter: chapter,
                isReadOnly: isReadOnly
            )

            if !isReadOnly {
                HStack {
                    Button("Rename…", systemImage: "pencil") {
                        titleEditor = .renaming(chapter)
                    }
                    .accessibilityIdentifier("chapter-rename")

                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        Task {
                            guard await editorModel.flushPendingSave() else { return }
                            await model.duplicateSelectedChapter()
                        }
                    }
                    .accessibilityIdentifier("chapter-duplicate")

                    Spacer()

                    Button("Delete…", systemImage: "trash", role: .destructive) {
                        deletionCandidate = chapter
                    }
                    .accessibilityIdentifier("chapter-delete")
                    .confirmationDialog(
                        deletionTitle,
                        isPresented: Binding(
                            get: { deletionCandidate != nil },
                            set: { isPresented in
                                if !isPresented {
                                    deletionCandidate = nil
                                }
                            }
                        ),
                        titleVisibility: .visible,
                        presenting: deletionCandidate
                    ) { chapter in
                        Button("Delete Chapter", role: .destructive) {
                            deletionCandidate = nil
                            Task {
                                guard await editorModel.flushPendingSave() else { return }
                                await model.deleteChapter(id: chapter.id)
                            }
                        }
                        .accessibilityIdentifier("chapter-confirm-delete")
                        Button("Cancel", role: .cancel) {
                            deletionCandidate = nil
                        }
                    } message: { chapter in
                        Text("“\(chapter.title)” can be restored with Undo while this Book Info window remains open.")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(model.isPerformingOperation)
            }
        }
    }

    private func deletionUndoBanner(_ deletion: ChapterDeletion) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
            Text("Deleted “\(deletion.chapter.title)”.")
                .font(.callout)
                .lineLimit(1)
            Spacer()
            Button("Undo") {
                Task {
                    guard await editorModel.flushPendingSave() else { return }
                    await model.undoLastDeletion()
                }
            }
            .disabled(model.isPerformingOperation || isReadOnly)
            .accessibilityIdentifier("chapter-undo-delete")
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("chapter-deletion-undo")
    }

    private var summaryDescription: String {
        let summary = model.summary
        let chapterDescription = summary.chapterCount == 1
            ? "1 Chapter"
            : "\(summary.chapterCount) Chapters"
        return "\(chapterDescription) • \(wordDescription(summary.wordCount))"
    }

    private func wordDescription(_ count: Int) -> String {
        count == 1 ? "1 word" : "\(count) words"
    }

    private var deletionTitle: String {
        guard let deletionCandidate else { return "Delete chapter?" }
        return "Delete “\(deletionCandidate.title)”?"
    }
}

private struct ChapterTitleEditorConfiguration: Identifiable {
    enum Mode {
        case add
        case rename
    }

    let id = UUID()
    let mode: Mode
    let title: String

    var navigationTitle: String {
        switch mode {
        case .add:
            "Add Chapter"
        case .rename:
            "Rename Chapter"
        }
    }

    var saveTitle: String {
        switch mode {
        case .add:
            "Add"
        case .rename:
            "Rename"
        }
    }

    static func adding() -> Self {
        Self(mode: .add, title: "Untitled Chapter")
    }

    static func renaming(_ chapter: Chapter) -> Self {
        Self(mode: .rename, title: chapter.title)
    }
}

private struct ChapterTitleEditorSheet: View {
    let configuration: ChapterTitleEditorConfiguration
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var title: String
    @State private var errorMessage: String?
    @FocusState private var isTitleFocused: Bool

    init(
        configuration: ChapterTitleEditorConfiguration,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String) -> Void
    ) {
        self.configuration = configuration
        self.onCancel = onCancel
        self.onSave = onSave
        _title = State(initialValue: configuration.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(configuration.navigationTitle)
                .font(.title2.bold())

            TextField("Chapter Title", text: $title)
                .focused($isTitleFocused)
                .onSubmit(save)
                .accessibilityIdentifier("chapter-title-field")

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("chapter-title-error")
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(configuration.saveTitle) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("chapter-title-save")
            }
        }
        .padding(24)
        .frame(width: 420)
        .task {
            isTitleFocused = true
        }
    }

    private func save() {
        do {
            let validatedTitle = try ChapterTitleInput(title: title).validated()
            errorMessage = nil
            onSave(validatedTitle)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
