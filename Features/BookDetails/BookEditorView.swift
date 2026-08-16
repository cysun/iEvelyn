import SwiftUI
import UniformTypeIdentifiers

nonisolated struct BookEditorConfiguration: Identifiable, Sendable {
    let id: UUID
    let bookID: UUID?
    let metadata: BookMetadataInput
    let hasCover: Bool

    static func adding() -> BookEditorConfiguration {
        BookEditorConfiguration(id: UUID(), bookID: nil, metadata: .empty, hasCover: false)
    }

    static func editing(_ book: LibraryBook) -> BookEditorConfiguration {
        BookEditorConfiguration(
            id: book.id,
            bookID: book.id,
            metadata: book.metadataInput,
            hasCover: book.coverAsset != nil
        )
    }

    var title: String {
        bookID == nil ? "Add Book" : "Edit Book"
    }
}

struct BookEditorView: View {
    let configuration: BookEditorConfiguration
    let onCancel: () -> Void
    let onSave: (BookEditorSubmission) async throws -> Void

    @State private var metadata: BookMetadataInput
    @State private var contentFileURL: URL?
    @State private var contentMode = BookContentFileMode.replace
    @State private var coverUpdate = BookCoverUpdate.unchanged
    @State private var fileImportKind = BookEditorFileImportKind.content
    @State private var isFileImporterPresented = false
    @State private var showsMoreOptions = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        configuration: BookEditorConfiguration,
        onCancel: @escaping () -> Void,
        onSave: @escaping (BookEditorSubmission) async throws -> Void
    ) {
        self.configuration = configuration
        self.onCancel = onCancel
        self.onSave = onSave
        _metadata = State(initialValue: configuration.metadata)
        _contentFileURL = State(
            initialValue: configuration.bookID == nil ? Self.uiTestingContentFileURL() : nil
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Book") {
                    TextField("Title", text: $metadata.title)
                        .accessibilityIdentifier("book-editor-title")

                    if showsMoreOptions {
                        TextField("Subtitle", text: $metadata.subtitle)
                            .accessibilityIdentifier("book-editor-subtitle")
                    }

                    Toggle("Show More Options", isOn: $showsMoreOptions)
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("book-editor-show-more-options")
                }

                Section(showsMoreOptions ? "Authors" : "Author") {
                    ForEach(metadata.authors.indices, id: \.self) { index in
                        if showsMoreOptions || index == metadata.authors.startIndex {
                            HStack {
                                TextField(
                                    showsMoreOptions ? "Author \(index + 1)" : "Author",
                                    text: $metadata.authors[index]
                                )
                                .accessibilityIdentifier("book-editor-author-\(index)")

                                if showsMoreOptions {
                                    Button("Move Author Up", systemImage: "arrow.up") {
                                        metadata.authors.swapAt(index, index - 1)
                                    }
                                    .labelStyle(.iconOnly)
                                    .disabled(index == metadata.authors.startIndex)

                                    Button("Move Author Down", systemImage: "arrow.down") {
                                        metadata.authors.swapAt(index, index + 1)
                                    }
                                    .labelStyle(.iconOnly)
                                    .disabled(index == metadata.authors.index(before: metadata.authors.endIndex))

                                    Button("Remove Author", systemImage: "minus.circle") {
                                        metadata.authors.remove(at: index)
                                    }
                                    .labelStyle(.iconOnly)
                                    .disabled(metadata.authors.count == 1)
                                }
                            }
                        }
                    }

                    if showsMoreOptions {
                        Button("Add Author", systemImage: "plus") {
                            metadata.authors.append("")
                        }
                        .accessibilityIdentifier("book-editor-add-author")
                    }
                }

                if showsMoreOptions {
                    Section("Tags") {
                        ForEach(metadata.tags.indices, id: \.self) { index in
                            HStack {
                                TextField("Tag \(index + 1)", text: $metadata.tags[index])
                                    .accessibilityIdentifier("book-editor-tag-\(index)")

                                Button("Remove Tag", systemImage: "minus.circle") {
                                    metadata.tags.remove(at: index)
                                }
                                .labelStyle(.iconOnly)
                            }
                        }

                        Button("Add Tag", systemImage: "plus") {
                            metadata.tags.append("")
                        }
                        .accessibilityIdentifier("book-editor-add-tag")
                    }
                }

                Section("Content") {
                    LabeledContent("File") {
                        Text(contentFileURL?.lastPathComponent ?? contentPlaceholder)
                            .foregroundStyle(contentFileURL == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .accessibilityIdentifier("book-editor-content-file")
                    }

                    Button("Choose Content File…", systemImage: "doc.badge.plus") {
                        presentFileImporter(for: .content)
                    }
                    .accessibilityIdentifier("book-editor-choose-content")

                    if configuration.bookID != nil {
                        Picker("When a file is selected", selection: $contentMode) {
                            Text("Replace existing content").tag(BookContentFileMode.replace)
                            Text("Append chapters").tag(BookContentFileMode.append)
                        }
                        .pickerStyle(.radioGroup)
                        .accessibilityIdentifier("book-editor-content-mode")

                        Text(
                            contentFileURL == nil
                                ? "Leave the file unselected to keep the existing chapters."
                                : contentModeHelp
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Required. The file must start with # Book Title and one or more ### author headings. Level-2 headings define chapters.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Cover") {
                    LabeledContent("Change") {
                        Text(coverDescription)
                            .foregroundStyle(coverDescriptionIsSecondary ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .accessibilityIdentifier("book-editor-cover-file")
                    }

                    HStack {
                        Button("Choose Cover…", systemImage: "photo.badge.plus") {
                            presentFileImporter(for: .cover)
                        }
                        .accessibilityIdentifier("book-editor-choose-cover")

                        switch coverUpdate {
                        case .replace:
                            Button("Clear Selection") {
                                coverUpdate = .unchanged
                            }
                        case .remove:
                            Button("Keep Current Cover") {
                                coverUpdate = .unchanged
                            }
                        case .unchanged:
                            if configuration.hasCover {
                                Button("Remove Cover", systemImage: "photo.badge.minus", role: .destructive) {
                                    coverUpdate = .remove
                                }
                                .accessibilityIdentifier("book-editor-remove-cover")
                            }
                        }
                    }

                    Text("Optional. JPEG, PNG, and HEIC images are supported; 2:3 artwork avoids cropping.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if showsMoreOptions {
                    Section("Description") {
                        TextEditor(text: $metadata.summary)
                            .frame(minHeight: 96)
                            .accessibilityLabel("Summary")
                            .accessibilityIdentifier("book-editor-summary")
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("book-editor-error")
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Saving book")
                }

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
                .accessibilityIdentifier("book-editor-save")
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: showsMoreOptions ? 680 : 540)
        .navigationTitle(configuration.title)
        .disabled(isSaving)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: fileImportTypes,
            allowsMultipleSelection: false
        ) { result in
            receiveSelection(result, for: fileImportKind)
        }
    }

    private var contentPlaceholder: String {
        configuration.bookID == nil ? "Required" : "Keep existing content"
    }

    private var contentModeHelp: String {
        switch contentMode {
        case .replace:
            "The file must include the book title and author preamble. Its chapters replace the current content."
        case .append:
            "The file must contain only level-2 chapter sections. They are added after the current last chapter."
        }
    }

    private var coverDescription: String {
        switch coverUpdate {
        case .unchanged:
            configuration.hasCover ? "Keep current cover" : "No cover"
        case .replace(let sourceURL):
            sourceURL.lastPathComponent
        case .remove:
            "Remove current cover"
        }
    }

    private var coverDescriptionIsSecondary: Bool {
        if case .unchanged = coverUpdate { return true }
        return false
    }

    private var bookContentImportTypes: [UTType] {
        var types: [UTType] = [.plainText]
        for fileExtension in ["md", "markdown"] {
            if let type = UTType(filenameExtension: fileExtension), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }

    private var fileImportTypes: [UTType] {
        switch fileImportKind {
        case .content:
            bookContentImportTypes
        case .cover:
            [.jpeg, .png, .heic]
        }
    }

    private func presentFileImporter(for kind: BookEditorFileImportKind) {
        fileImportKind = kind
        isFileImporterPresented = true
    }

    private func receiveSelection(
        _ result: Result<[URL], Error>,
        for kind: BookEditorFileImportKind
    ) {
        switch result {
        case .success(let urls):
            guard let sourceURL = urls.first else { return }
            errorMessage = nil
            switch kind {
            case .content:
                contentFileURL = sourceURL
            case .cover:
                coverUpdate = .replace(sourceURL)
            }
        case .failure(let error):
            guard (error as NSError).code != NSUserCancelledError else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        errorMessage = nil
        isSaving = true
        let submission = BookEditorSubmission(
            metadata: metadata,
            contentFileURL: contentFileURL,
            contentMode: contentMode,
            coverUpdate: coverUpdate
        )

        Task {
            do {
                try await onSave(submission)
            } catch is CancellationError {
                // Dismissal cancels the save without presenting a stale error.
            } catch {
                if metadata.authors.count > 1 || !metadata.tags.isEmpty {
                    showsMoreOptions = true
                }
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private static func uiTestingContentFileURL(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
#if DEBUG
        guard arguments.contains("--ui-testing"),
              let encodedContent = environment["IEVELYN_UI_TEST_CONTENT_BASE64"],
              let data = Data(base64Encoded: encodedContent) else {
            return nil
        }
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "ui-test-book-\(UUID().databaseString).txt")
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            assertionFailure("Could not prepare the UI-test content fixture: \(error)")
            return nil
        }
#else
        return nil
#endif
    }
}

private enum BookEditorFileImportKind {
    case content
    case cover
}
