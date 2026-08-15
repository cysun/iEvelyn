import SwiftUI

nonisolated struct BookEditorConfiguration: Identifiable, Sendable {
    let id: UUID
    let bookID: UUID?
    let metadata: BookMetadataInput

    static func adding() -> BookEditorConfiguration {
        BookEditorConfiguration(id: UUID(), bookID: nil, metadata: .empty)
    }

    static func editing(_ book: LibraryBook) -> BookEditorConfiguration {
        BookEditorConfiguration(id: book.id, bookID: book.id, metadata: book.metadataInput)
    }

    var title: String {
        bookID == nil ? "Add Book" : "Edit Book"
    }
}

struct BookEditorView: View {
    let configuration: BookEditorConfiguration
    let onCancel: () -> Void
    let onSave: (BookMetadataInput) async throws -> Void

    @State private var metadata: BookMetadataInput
    @State private var includesPublicationDate: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        configuration: BookEditorConfiguration,
        onCancel: @escaping () -> Void,
        onSave: @escaping (BookMetadataInput) async throws -> Void
    ) {
        self.configuration = configuration
        self.onCancel = onCancel
        self.onSave = onSave
        _metadata = State(initialValue: configuration.metadata)
        _includesPublicationDate = State(initialValue: configuration.metadata.publicationDate != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Book") {
                    TextField("Title", text: $metadata.title)
                        .accessibilityIdentifier("book-editor-title")
                    TextField("Subtitle", text: $metadata.subtitle)
                        .accessibilityIdentifier("book-editor-subtitle")
                }

                Section("Authors") {
                    ForEach(metadata.authors.indices, id: \.self) { index in
                        HStack {
                            TextField("Author \(index + 1)", text: $metadata.authors[index])
                                .accessibilityIdentifier("book-editor-author-\(index)")

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

                    Button("Add Author", systemImage: "plus") {
                        metadata.authors.append("")
                    }
                    .accessibilityIdentifier("book-editor-add-author")
                }

                Section("Description") {
                    TextEditor(text: $metadata.summary)
                        .frame(minHeight: 96)
                        .accessibilityLabel("Summary")
                        .accessibilityIdentifier("book-editor-summary")
                }

                Section("Publication") {
                    TextField("Language", text: $metadata.languageCode)
                        .accessibilityIdentifier("book-editor-language")
                    TextField("Publisher", text: $metadata.publisher)
                        .accessibilityIdentifier("book-editor-publisher")

                    Toggle("Publication Date", isOn: $includesPublicationDate)
                        .accessibilityIdentifier("book-editor-publication-date-toggle")

                    if includesPublicationDate {
                        DatePicker(
                            "Published",
                            selection: Binding(
                                get: { metadata.publicationDate ?? .now },
                                set: { metadata.publicationDate = $0 }
                            ),
                            displayedComponents: .date
                        )
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
            .onChange(of: includesPublicationDate) { _, includesDate in
                if includesDate {
                    metadata.publicationDate = metadata.publicationDate ?? .now
                } else {
                    metadata.publicationDate = nil
                }
            }

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
        .frame(minWidth: 560, minHeight: 610)
        .navigationTitle(configuration.title)
        .disabled(isSaving)
    }

    private func save() {
        errorMessage = nil
        isSaving = true

        Task {
            do {
                try await onSave(metadata)
            } catch is CancellationError {
                // Dismissal cancels the save without presenting a stale error.
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
