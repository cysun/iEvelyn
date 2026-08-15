import SwiftUI

struct LibraryRootView: View {
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
        } content: {
            LibraryContentView(model: model) {
                editorConfiguration = .adding()
            }
        } detail: {
            BookDetailView(
                book: model.selectedBook,
                isBusy: model.isPerformingOperation,
                onEdit: { book in
                    editorConfiguration = .editing(book)
                },
                onToggleFavorite: { book in
                    Task { await model.toggleFavorite(for: book) }
                },
                onMoveToTrash: { book in
                    Task { await model.moveToTrash(book) }
                },
                onRestore: { book in
                    Task { await model.restore(book) }
                },
                onDeletePermanently: { book in
                    Task { await model.permanentlyDelete(book) }
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
        .onChange(of: model.selectedBookID) { _, _ in
            guard let book = model.selectedBook, !book.isTrashed else { return }
            Task {
                await model.markOpened(book)
            }
        }
        .sheet(item: $editorConfiguration) { configuration in
            BookEditorView(
                configuration: configuration,
                onCancel: {
                    editorConfiguration = nil
                },
                onSave: { metadata in
                    try await model.saveBook(id: configuration.bookID, metadata: metadata)
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
