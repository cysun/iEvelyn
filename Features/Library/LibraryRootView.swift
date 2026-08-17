import SwiftUI
import UniformTypeIdentifiers

struct LibraryRootView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var model: LibraryViewModel
    @State private var editorConfiguration: BookEditorConfiguration?
    @State private var exportPresentation: BookExportPresentation?
    @State private var isExportingBook = false
    @State private var didRestoreSceneState = false
    @FocusState private var isSearchFocused: Bool
    @SceneStorage("library.destination") private var storedDestination = LibraryDestination.allBooks.rawValue
    @SceneStorage("library.presentation") private var storedPresentation = LibraryPresentation.grid.rawValue
    @SceneStorage("library.sortOrder") private var storedSortOrder = LibrarySortOrder.title.rawValue

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
                    openWindow(
                        id: SceneIdentifier.reader,
                        value: ReaderWindowRoute(bookID: book.id)
                    )
                    Task { await model.markOpened(book) }
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
                    openWindow(
                        id: SceneIdentifier.reader,
                        value: ReaderWindowRoute(
                            bookID: result.bookID,
                            searchTarget: searchTarget
                        )
                    )
                    Task { await model.markOpened(book) }
                },
                onEditBook: { book in
                    editorConfiguration = .editing(book)
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
                }
            )
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
        .sheet(item: $editorConfiguration) { configuration in
            BookEditorView(
                configuration: configuration,
                onCancel: {
                    editorConfiguration = nil
                },
                onSave: { submission in
                    try await model.saveBook(id: configuration.bookID, submission: submission)
                    editorConfiguration = nil
                }
            )
        }
        .fileExporter(
            isPresented: $isExportingBook,
            document: exportPresentation.map { BookExportDocument(data: $0.data) },
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
        model.sortOrder = LibrarySortOrder(rawValue: storedSortOrder) ?? .title
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

private struct BookExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [EPUBExportDocument.contentType, MarkdownExportDocument.contentType]
    }

    static var writableContentTypes: [UTType] { readableContentTypes }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
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
