import SwiftUI

struct LibraryContentView: View {
    @Bindable var model: LibraryViewModel
    let onAddBook: () -> Void
    let onOpenBook: (LibraryBook) -> Void
    let onEditBook: (LibraryBook) -> Void

    @State private var permanentDeletionCandidate: LibraryBook?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.isLoading {
                loadingState
            } else if let errorMessage = model.errorMessage {
                errorState(message: errorMessage)
            } else if model.visibleBooks.isEmpty {
                emptyState
            } else {
                switch model.presentation {
                case .grid:
                    LibraryGridView(
                        books: model.visibleBooks,
                        loadCoverImage: model.loadCoverImage,
                        onCoverLoadError: model.reportCoverLoadFailure,
                        onOpenBook: onOpenBook,
                        onBookAction: handleBookAction
                    )
                case .list:
                    LibraryListView(
                        books: model.visibleBooks,
                        onOpenBook: onOpenBook,
                        onBookAction: handleBookAction
                    )
                }
            }
        }
        .navigationTitle(model.destination.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Add Book", systemImage: "plus") {
                    onAddBook()
                }
                .help("Add a book")
                .accessibilityIdentifier("library-add-book")

                sortMenu
                presentationPicker
            }
        }
        .confirmationDialog(
            permanentDeletionTitle,
            isPresented: Binding(
                get: { permanentDeletionCandidate != nil },
                set: { isPresented in
                    if !isPresented {
                        permanentDeletionCandidate = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: permanentDeletionCandidate
        ) { book in
            Button("Delete Permanently", role: .destructive) {
                permanentDeletionCandidate = nil
                Task {
                    await model.permanentlyDelete(book)
                }
            }
            .accessibilityIdentifier("book-confirm-delete-permanently")

            Button("Cancel", role: .cancel) {
                permanentDeletionCandidate = nil
            }
        } message: { _ in
            Text("This cannot be undone. All data owned by this book will be removed.")
        }
    }

    private var loadingState: some View {
        ContentUnavailableView {
            ProgressView()
            Text("Loading Books")
        } description: {
            Text("Reading the local library…")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("library-books-loading")
    }

    private func errorState(message: String) -> some View {
        ContentUnavailableView {
            Label("Could Not Load Books", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task {
                    await model.observeLibrary()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("library-books-error")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.destination.title)
                .font(.title2.bold())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.destination.title)
                .accessibilityIdentifier("library-content-title")

            Spacer()

            Text(bookCountDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .accessibilityIdentifier("library-book-count")
        }
        .padding(.horizontal, LibraryDesignTokens.contentPadding)
        .padding(.vertical, 16)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyStateTitle, systemImage: emptyStateSystemImage)
        } description: {
            Text(emptyStateDescription)
        } actions: {
            if hasSearchText {
                Button("Clear Search") {
                    model.clearSearch()
                }
                .keyboardShortcut(.cancelAction)
            } else if model.destination != .trash {
                Button("Add Book") {
                    onAddBook()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("library-empty-state")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $model.sortOrder) {
                ForEach(LibrarySortOrder.allCases) { sortOrder in
                    Text(sortOrder.title)
                        .tag(sortOrder)
                }
            }
        } label: {
            Label("Sort: \(model.sortOrder.title)", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort books")
        .accessibilityIdentifier("library-sort-menu")
    }

    private var presentationPicker: some View {
        Picker("Presentation", selection: $model.presentation) {
            ForEach(LibraryPresentation.allCases) { presentation in
                Image(systemName: presentation.systemImage)
                    .accessibilityLabel(presentation.title)
                    .accessibilityIdentifier("library-view-\(presentation.rawValue)")
                    .tag(presentation)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Switch between grid and list views")
    }

    private var bookCountDescription: String {
        let count = model.visibleBooks.count
        return count == 1 ? "1 Book" : "\(count) Books"
    }

    private var hasSearchText: Bool {
        !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var permanentDeletionTitle: String {
        guard let book = permanentDeletionCandidate else {
            return "Delete book permanently?"
        }
        return "Delete “\(book.title)” permanently?"
    }

    private func handleBookAction(_ book: LibraryBook, _ action: BookManagementAction) {
        switch action {
        case .edit:
            onEditBook(book)
        case .toggleFavorite:
            Task {
                await model.toggleFavorite(for: book)
            }
        case .moveToTrash:
            Task {
                await model.moveToTrash(book)
            }
        case .restore:
            Task {
                await model.restore(book)
            }
        case .requestPermanentDeletion:
            permanentDeletionCandidate = book
        }
    }

    private var emptyStateTitle: String {
        if hasSearchText {
            return "No Results"
        }

        if model.destination == .trash {
            return "Trash is Empty"
        }

        return "No Books Here"
    }

    private var emptyStateSystemImage: String {
        if hasSearchText {
            return "magnifyingglass"
        }

        return model.destination == .trash ? "trash" : "books.vertical"
    }

    private var emptyStateDescription: String {
        if hasSearchText {
            return "No books in \(model.destination.title) match “\(model.searchText)”."
        }

        if model.destination == .trash {
            return "Books you remove will remain here until they are permanently deleted."
        }

        return "This collection does not contain any books yet."
    }
}
