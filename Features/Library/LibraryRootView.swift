import SwiftUI

struct LibraryRootView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var model: LibraryViewModel
    @State private var editorConfiguration: BookEditorConfiguration?
    @State private var exportPresentation: EPUBExportPresentation?
    @State private var isExportingEPUB = false

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
                        exportPresentation = preparedExport
                        isExportingEPUB = true
                    }
                }
            )
        }
        .searchable(
            text: $model.searchText,
            placement: .toolbar,
            prompt: "Search Library"
        )
        .focusedSceneValue(\.libraryPresentation, $model.presentation)
        .focusedSceneValue(\.libraryDestination, $model.destination)
        .accessibilityIdentifier("library-root")
        .task {
            await model.observeLibrary()
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
            isPresented: $isExportingEPUB,
            document: exportPresentation.map { EPUBExportDocument(data: $0.file.data) },
            contentType: EPUBExportDocument.contentType,
            defaultFilename: exportPresentation?.file.suggestedFilename ?? "Untitled Book.epub"
        ) { result in
            isExportingEPUB = false
            exportPresentation = nil
            if case .failure(let error) = result,
               (error as? CocoaError)?.code != .userCancelled {
                model.reportEPUBFileWriteFailure(error)
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
