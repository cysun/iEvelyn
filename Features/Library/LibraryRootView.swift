import SwiftUI
import UniformTypeIdentifiers

struct LibraryRootView: View {
    @State private var model: LibraryViewModel
    @State private var editorConfiguration: BookEditorConfiguration?
    @State private var bookInfoPresentation: BookInfoPresentation?
    @State private var readerPresentation: ReaderPresentation?
    @State private var coverImportBookID: UUID?
    @State private var isCoverImporterPresented = false

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
                    if book.isTrashed {
                        showBookInfo(book)
                    } else {
                        readerPresentation = ReaderPresentation(id: book.id, title: book.title)
                    }
                },
                onShowBookInfo: { book in
                    showBookInfo(book)
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
                onSave: { metadata in
                    try await model.saveBook(id: configuration.bookID, metadata: metadata)
                    editorConfiguration = nil
                }
            )
        }
        .sheet(item: $bookInfoPresentation) { presentation in
            NavigationStack {
                BookDetailView(
                    book: model.book(id: presentation.id),
                    chapterModel: presentation.chapterModel,
                    chapterEditorModel: presentation.chapterEditorModel,
                    isBusy: model.isPerformingOperation,
                    loadCoverImage: model.loadCoverImage,
                    onCoverLoadError: model.reportCoverLoadFailure,
                    onEdit: { book in
                        Task {
                            guard await presentation.chapterEditorModel.flushPendingSave() else { return }
                            presentEditorAfterClosingBookInfo(for: book)
                        }
                    },
                    onToggleFavorite: { book in
                        Task { await model.toggleFavorite(for: book) }
                    },
                    onMoveToTrash: { book in
                        Task {
                            guard await presentation.chapterEditorModel.flushPendingSave() else { return }
                            bookInfoPresentation = nil
                            await model.moveToTrash(book)
                        }
                    },
                    onRestore: { book in
                        bookInfoPresentation = nil
                        Task { await model.restore(book) }
                    },
                    onDeletePermanently: { book in
                        bookInfoPresentation = nil
                        Task { await model.permanentlyDelete(book) }
                    },
                    onChooseCover: { book in
                        coverImportBookID = book.id
                        isCoverImporterPresented = true
                    },
                    onRemoveCover: { book in
                        Task { await model.removeCover(from: book) }
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            Task {
                                guard await presentation.chapterEditorModel.flushPendingSave() else { return }
                                bookInfoPresentation = nil
                            }
                        }
                        .keyboardShortcut(.cancelAction)
                    }
                }
            }
            .frame(minWidth: 580, idealWidth: 680, minHeight: 640, idealHeight: 760)
            .interactiveDismissDisabled(presentation.chapterEditorModel.shouldPreventDismissal)
        }
        .sheet(item: $readerPresentation) { presentation in
            VStack(spacing: 18) {
                Image(systemName: "book.closed")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)

                Text("Reader Not Available Yet")
                    .font(.title2.bold())

                Text("The reading view for “\(presentation.title)” has not been implemented yet. Use the book's More menu for information and editing.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 380)

                Button("OK") {
                    readerPresentation = nil
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("reader-unavailable-dismiss")
            }
            .padding(32)
            .frame(minWidth: 460, minHeight: 260)
        }
        .fileImporter(
            isPresented: $isCoverImporterPresented,
            allowedContentTypes: [.jpeg, .png, .heic],
            allowsMultipleSelection: false
        ) { result in
            let bookID = coverImportBookID
            coverImportBookID = nil

            switch result {
            case .success(let urls):
                guard let bookID, let sourceURL = urls.first else { return }
                Task {
                    await model.importCover(for: bookID, from: sourceURL)
                }
            case .failure(let error):
                guard (error as NSError).code != NSUserCancelledError else { return }
                model.reportCoverImporterFailure(error)
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

    private func presentEditorAfterClosingBookInfo(for book: LibraryBook) {
        bookInfoPresentation = nil
        Task { @MainActor in
            await Task.yield()
            editorConfiguration = .editing(book)
        }
    }

    private func showBookInfo(_ book: LibraryBook) {
        bookInfoPresentation = BookInfoPresentation(
            id: book.id,
            chapterModel: model.makeChapterManagementModel(for: book.id),
            chapterEditorModel: model.makeChapterEditorModel()
        )
    }
}

private struct BookInfoPresentation: Identifiable {
    let id: LibraryBook.ID
    let chapterModel: ChapterManagementViewModel
    let chapterEditorModel: ChapterEditorViewModel
}

private struct ReaderPresentation: Identifiable {
    let id: LibraryBook.ID
    let title: String
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
