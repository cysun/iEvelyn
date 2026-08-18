import SwiftUI
import UniformTypeIdentifiers

struct LibraryRootView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var model: LibraryViewModel
    @State private var editorConfiguration: BookEditorConfiguration?
    @State private var coverManagerBook: LibraryBook?
    @State private var pendingBookIDToOpen: UUID?
    @State private var exportPresentation: BookExportPresentation?
    @State private var batchExportPresentation: BookBatchExportPresentation?
    @State private var isExportingBook = false
    @State private var isExportingBooks = false
    @State private var didRestoreSceneState = false
    @FocusState private var isSearchFocused: Bool
    @SceneStorage("library.destination") private var storedDestination = LibraryDestination.allBooks.rawValue
    @SceneStorage("library.presentation") private var storedPresentation = LibraryPresentation.grid.rawValue
    @SceneStorage("library.sortOrder") private var storedSortOrder = LibrarySortOrder.recentlyOpened.rawValue

    init(repository: any LibraryRepository) {
        _model = State(initialValue: LibraryViewModel(repository: repository))
    }

    init(model: LibraryViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            LibrarySidebarView(selection: $model.destination)
        } detail: {
            LibraryContentView(
                model: model,
                onAddBook: {
                    editorConfiguration = .adding()
                },
                onOpenBook: { book in
                    guard !book.isTrashed else { return }
                    openBook(bookID: book.id)
                },
                onOpenSearchResult: { result in
                    guard let book = model.book(id: result.bookID), !book.isTrashed else { return }
                    let searchTarget = result.chapterID.map { chapterID in
                        ReaderSearchTarget(
                            chapterID: chapterID,
                            stableBlockID: result.stableBlockID,
                            textQuote: result.textQuote,
                            fractionInChapter: result.fractionInChapter
                        )
                    }
                    openBook(bookID: result.bookID, searchTarget: searchTarget)
                },
                onEditBook: { book in
                    editorConfiguration = .editing(book)
                },
                onManageCovers: { book in
                    coverManagerBook = book
                },
                onExportBook: { book in
                    Task {
                        guard let preparedExport = await model.prepareEPUBExport(for: book) else {
                            return
                        }
                        exportPresentation = .epub(preparedExport)
                        isExportingBook = true
                    }
                },
                onExportMarkdown: { book in
                    Task {
                        guard let preparedExport = await model.prepareMarkdownExport(for: book) else {
                            return
                        }
                        exportPresentation = .markdown(preparedExport)
                        isExportingBook = true
                    }
                },
                onExportBooksAsEPUB: { books in
                    guard let preparedExports = await model.prepareEPUBExports(for: books) else {
                        return false
                    }
                    batchExportPresentation = .epub(preparedExports)
                    isExportingBooks = true
                    return true
                },
                onExportBooksAsMarkdown: { books in
                    guard let preparedExports = await model.prepareMarkdownExports(for: books) else {
                        return false
                    }
                    batchExportPresentation = .markdown(preparedExports)
                    isExportingBooks = true
                    return true
                }
            )
            .fileExporter(
                isPresented: $isExportingBooks,
                documents: batchExportPresentation?.documents ?? [],
                contentType: batchExportPresentation?.contentType ?? .data
            ) { result in
                let completedPresentation = batchExportPresentation
                isExportingBooks = false
                batchExportPresentation = nil
                if case .failure(let error) = result,
                   (error as? CocoaError)?.code != .userCancelled {
                    switch completedPresentation?.kind {
                    case .epub:
                        model.reportEPUBFileWriteFailure(error)
                    case .markdown:
                        model.reportMarkdownFileWriteFailure(error)
                    case nil:
                        break
                    }
                }
            }
        }
        .searchable(
            text: $model.searchText,
            placement: .toolbar,
            prompt: "Search Library"
        )
        .searchFocused($isSearchFocused)
        .focusedSceneValue(\.libraryPresentation, $model.presentation)
        .focusedSceneValue(\.libraryDestination, $model.destination)
        .focusedSceneValue(\.librarySearchFocus, $isSearchFocused)
        .accessibilityIdentifier("library-root")
        .task {
            restoreSceneStateIfNeeded()
            await model.observeLibrary()
        }
        .onChange(of: model.destination) { _, destination in
            storedDestination = destination.rawValue
        }
        .onChange(of: model.presentation) { _, presentation in
            storedPresentation = presentation.rawValue
        }
        .onChange(of: model.sortOrder) { _, sortOrder in
            storedSortOrder = sortOrder.rawValue
        }
        .sheet(item: $editorConfiguration, onDismiss: openPendingBookIfNeeded) { configuration in
            BookEditorView(
                configuration: configuration,
                onCancel: {
                    editorConfiguration = nil
                },
                onSave: { submission in
                    let bookID = try await model.saveBook(
                        id: configuration.bookID,
                        submission: submission
                    )
                    pendingBookIDToOpen = bookID
                    editorConfiguration = nil
                }
            )
        }
        .sheet(item: $coverManagerBook) { book in
            CoverManagerView(book: book, model: model)
        }
        .fileExporter(
            isPresented: $isExportingBook,
            document: exportPresentation.map {
                BookExportDocument(data: $0.data, suggestedFilename: $0.suggestedFilename)
            },
            contentType: exportPresentation?.contentType ?? .data,
            defaultFilename: exportPresentation?.suggestedFilename ?? "Untitled Book"
        ) { result in
            let completedPresentation = exportPresentation
            isExportingBook = false
            exportPresentation = nil
            if case .failure(let error) = result,
               (error as? CocoaError)?.code != .userCancelled {
                switch completedPresentation {
                case .epub:
                    model.reportEPUBFileWriteFailure(error)
                case .markdown:
                    model.reportMarkdownFileWriteFailure(error)
                case nil:
                    break
                }
            }
        }
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func restoreSceneStateIfNeeded() {
        guard !didRestoreSceneState else { return }
        didRestoreSceneState = true
        model.destination = LibraryDestination(rawValue: storedDestination) ?? .allBooks
        model.presentation = LibraryPresentation(rawValue: storedPresentation) ?? .grid
        model.sortOrder = LibrarySortOrder(rawValue: storedSortOrder) ?? .recentlyOpened
    }

    private func openBook(bookID: UUID, searchTarget: ReaderSearchTarget? = nil) {
        openWindow(
            id: SceneIdentifier.reader,
            value: ReaderWindowRoute(bookID: bookID, searchTarget: searchTarget)
        )
        Task { await model.markOpened(bookID: bookID) }
    }

    private func openPendingBookIfNeeded() {
        guard let bookID = pendingBookIDToOpen else { return }
        pendingBookIDToOpen = nil
        openBook(bookID: bookID)
    }
}

private enum BookExportPresentation {
    case epub(EPUBExportPresentation)
    case markdown(MarkdownExportPresentation)

    var data: Data {
        switch self {
        case .epub(let presentation):
            presentation.file.data
        case .markdown(let presentation):
            presentation.file.data
        }
    }

    var contentType: UTType {
        switch self {
        case .epub:
            EPUBExportDocument.contentType
        case .markdown:
            MarkdownExportDocument.contentType
        }
    }

    var suggestedFilename: String {
        switch self {
        case .epub(let presentation):
            presentation.file.suggestedFilename
        case .markdown(let presentation):
            presentation.file.suggestedFilename
        }
    }
}

private struct BookBatchExportPresentation {
    enum Kind {
        case epub
        case markdown
    }

    let kind: Kind
    let documents: [BookExportDocument]
    let contentType: UTType

    static func epub(_ presentations: [EPUBExportPresentation]) -> Self {
        let filenames = BookBatchFilename.uniqued(
            presentations.map(\.file.suggestedFilename)
        )
        return Self(
            kind: .epub,
            documents: zip(presentations, filenames).map { presentation, filename in
                BookExportDocument(
                    data: presentation.file.data,
                    suggestedFilename: filename
                )
            },
            contentType: EPUBExportDocument.contentType
        )
    }

    static func markdown(_ presentations: [MarkdownExportPresentation]) -> Self {
        let filenames = BookBatchFilename.uniqued(
            presentations.map(\.file.suggestedFilename)
        )
        return Self(
            kind: .markdown,
            documents: zip(presentations, filenames).map { presentation, filename in
                BookExportDocument(
                    data: presentation.file.data,
                    suggestedFilename: filename
                )
            },
            contentType: MarkdownExportDocument.contentType
        )
    }
}

nonisolated enum BookBatchFilename {
    static func uniqued(_ filenames: [String]) -> [String] {
        var usedNames = Set<String>()
        return filenames.map { filename in
            let url = URL(fileURLWithPath: filename)
            let fileExtension = url.pathExtension
            let stem = url.deletingPathExtension().lastPathComponent
            var candidate = filename
            var suffix = 2
            while !usedNames.insert(normalized(candidate)).inserted {
                let numberedStem = "\(stem) \(suffix)"
                candidate = fileExtension.isEmpty
                    ? numberedStem
                    : "\(numberedStem).\(fileExtension)"
                suffix += 1
            }
            return candidate
        }
    }

    private static func normalized(_ filename: String) -> String {
        filename.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}

private struct BookExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [EPUBExportDocument.contentType, MarkdownExportDocument.contentType]
    }

    static var writableContentTypes: [UTType] { readableContentTypes }

    let data: Data
    let suggestedFilename: String

    init(data: Data, suggestedFilename: String) {
        self.data = data
        self.suggestedFilename = suggestedFilename
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
        suggestedFilename = "Untitled Book"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = suggestedFilename
        return wrapper
    }
}

#if DEBUG
#Preview {
    let books = SampleLibrary.previewBooks()
    LibraryRootView(
        model: LibraryViewModel(
            repository: PreviewLibraryRepository(books: books),
            initialBooks: books
        )
    )
        .frame(width: 1120, height: 700)
}

#Preview("Empty library") {
    LibraryRootView(
        model: LibraryViewModel(
            repository: PreviewLibraryRepository(books: [])
        )
    )
        .frame(width: 900, height: 600)
}
#endif
