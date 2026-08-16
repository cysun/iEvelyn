import SwiftUI

struct LibraryRootView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var model: LibraryViewModel
    @State private var editorConfiguration: BookEditorConfiguration?

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
                onEditBook: { book in
                    editorConfiguration = .editing(book)
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
