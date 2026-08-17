import SwiftUI

struct LibraryContentView: View {
    @Bindable var model: LibraryViewModel
    let onAddBook: () -> Void
    let onOpenBook: (LibraryBook) -> Void
    let onOpenSearchResult: (LibrarySearchResult) -> Void
    let onEditBook: (LibraryBook) -> Void
    let onExportBook: (LibraryBook) -> Void
    let onExportMarkdown: (LibraryBook) -> Void
    let onExportBooksAsEPUB: ([LibraryBook]) async -> Bool
    let onExportBooksAsMarkdown: ([LibraryBook]) async -> Bool

    @State private var permanentDeletionCandidate: LibraryBook?
    @State private var batchConfirmation: LibraryBatchConfirmation?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.hasSearchQuery {
                LibrarySearchResultsView(
                    model: model,
                    onOpenResult: onOpenSearchResult
                )
            } else if model.isLoading {
                loadingState
            } else if let errorMessage = model.errorMessage {
                errorState(message: errorMessage)
            } else if model.visibleBooks.isEmpty {
                emptyState
            } else {
                if !model.organizationGroups.isEmpty {
                    organizationFilters
                    Divider()
                }
                bookCollection
            }
        }
        .navigationTitle(model.destination.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.isSelectingBooks {
                    selectionToolbar
                } else {
                    ordinaryToolbar
                }
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
        .confirmationDialog(
            batchConfirmationTitle,
            isPresented: Binding(
                get: { batchConfirmation != nil },
                set: { isPresented in
                    if !isPresented {
                        batchConfirmation = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: batchConfirmation
        ) { confirmation in
            switch confirmation {
            case .moveToTrash(let bookIDs):
                Button("Move to Trash", role: .destructive) {
                    batchConfirmation = nil
                    Task {
                        await model.moveBooksToTrash(bookIDs: bookIDs)
                    }
                }
                .accessibilityIdentifier("library-confirm-batch-trash")
            case .clearReadingProgress(let bookIDs):
                Button("Clear Reading Progress", role: .destructive) {
                    batchConfirmation = nil
                    Task {
                        await model.clearReadingProgress(bookIDs: bookIDs)
                    }
                }
                .accessibilityIdentifier("library-confirm-clear-progress")
            case .emptyTrash:
                Button("Empty Trash", role: .destructive) {
                    batchConfirmation = nil
                    Task {
                        await model.emptyTrash()
                    }
                }
                .accessibilityIdentifier("library-confirm-empty-trash")
            }

            Button("Cancel", role: .cancel) {
                batchConfirmation = nil
            }
        } message: { confirmation in
            Text(confirmation.message)
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

            if model.hasSearchQuery {
                Picker("Search Scope", selection: $model.searchScope) {
                    ForEach(LibrarySearchScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("library-search-scope")
            }

            Text(model.isSelectingBooks ? selectionCountDescription : bookCountDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .accessibilityIdentifier("library-book-count")

            if model.isPreparingEPUB || model.isPreparingMarkdown || model.isPerformingOperation {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Performing library operation")
                    .accessibilityIdentifier("library-operation-progress")
            }
        }
        .padding(.horizontal, LibraryDesignTokens.contentPadding)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var bookCollection: some View {
        switch model.presentation {
        case .grid:
            LibraryGridView(
                books: model.visibleBooks,
                loadCoverImage: model.loadCoverImage,
                onCoverLoadError: model.reportCoverLoadFailure,
                onOpenBook: onOpenBook,
                onBookAction: handleBookAction,
                isSelecting: model.isSelectingBooks,
                selectedBookIDs: model.selectedBookIDs,
                onToggleSelection: model.toggleBookSelection
            )
        case .list:
            LibraryListView(
                books: model.visibleBooks,
                onOpenBook: onOpenBook,
                onBookAction: handleBookAction,
                isSelecting: model.isSelectingBooks,
                selectedBookIDs: model.selectedBookIDs,
                onToggleSelection: model.toggleBookSelection
            )
        }
    }

    private var organizationFilters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                organizationFilterButton(
                    title: "All",
                    count: model.books.filter { !$0.isTrashed }.count,
                    identifier: nil
                )
                ForEach(model.organizationGroups) { group in
                    organizationFilterButton(
                        title: group.name,
                        count: group.bookCount,
                        identifier: group.id
                    )
                }
            }
            .padding(.horizontal, LibraryDesignTokens.contentPadding)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("library-organization-filters")
    }

    private func organizationFilterButton(
        title: String,
        count: Int,
        identifier: String?
    ) -> some View {
        let isSelected = model.selectedOrganizationID == identifier
        return Button {
            model.selectedOrganizationID = identifier
        } label: {
            HStack(spacing: 5) {
                Text(title)
                Text(count, format: .number)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .font(.callout)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) \(count == 1 ? "book" : "books")")
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
                .keyboardShortcut("n", modifiers: [.command, .shift])
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
        .accessibilityLabel("Sort")
        .accessibilityValue(model.sortOrder.title)
        .help("Sort books")
        .accessibilityIdentifier("library-sort-menu")
    }

    @ViewBuilder
    private var ordinaryToolbar: some View {
        Button("Add Book", systemImage: "plus") {
            onAddBook()
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .help("Add a book")
        .accessibilityIdentifier("library-add-book")

        if model.destination == .trash {
            Button("Empty Trash…", systemImage: "trash.slash", role: .destructive) {
                batchConfirmation = .emptyTrash(model.books.filter(\.isTrashed).count)
            }
            .disabled(model.books.allSatisfy { !$0.isTrashed })
            .help("Permanently delete every book in Trash")
            .accessibilityIdentifier("library-empty-trash")
        } else if !model.hasSearchQuery && !model.visibleBooks.isEmpty {
            Button("Select", systemImage: "checkmark.circle") {
                model.beginBookSelection()
            }
            .help("Select books for batch actions")
            .accessibilityIdentifier("library-select-books")
        }

        sortMenu
        presentationPicker
    }

    @ViewBuilder
    private var selectionToolbar: some View {
        Button("Cancel") {
            model.endBookSelection()
        }
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("library-cancel-selection")

        Button(
            model.areAllVisibleBooksSelected ? "Deselect All" : "Select All",
            systemImage: model.areAllVisibleBooksSelected
                ? "checkmark.circle.badge.xmark"
                : "checkmark.circle"
        ) {
            model.toggleSelectAllVisibleBooks()
        }
        .accessibilityIdentifier("library-select-all")

        Menu("Actions", systemImage: "ellipsis.circle") {
            Button("Export EPUBs…", systemImage: "square.and.arrow.up") {
                exportSelectedBooksAsEPUB()
            }

            Button("Export Markdown…", systemImage: "doc.plaintext") {
                exportSelectedBooksAsMarkdown()
            }

            Divider()

            Button("Clear Reading Progress…", systemImage: "arrow.counterclockwise") {
                batchConfirmation = .clearReadingProgress(model.selectedBooksWithProgress.map(\.id))
            }
            .disabled(model.selectedBooksWithProgress.isEmpty)

            Button("Move to Trash…", systemImage: "trash", role: .destructive) {
                batchConfirmation = .moveToTrash(model.selectedBooks.map(\.id))
            }
        }
        .disabled(model.selectedBooks.isEmpty || model.isPerformingOperation)
        .help("Actions for selected books")
        .accessibilityIdentifier("library-selection-actions")

        presentationPicker
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
        let count = model.hasSearchQuery
            ? model.visibleSearchResults.count
            : model.visibleBooks.count
        if model.hasSearchQuery {
            return count == 1 ? "1 Result" : "\(count) Results"
        }
        return count == 1 ? "1 Book" : "\(count) Books"
    }

    private var selectionCountDescription: String {
        let count = model.selectedBooks.count
        return count == 1 ? "1 Selected" : "\(count) Selected"
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
        case .exportEPUB:
            onExportBook(book)
        case .exportMarkdown:
            onExportMarkdown(book)
        case .toggleFavorite:
            Task {
                await model.toggleFavorite(for: book)
            }
        case .clearReadingProgress:
            Task {
                await model.clearReadingProgress(for: book)
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

    private func exportSelectedBooksAsEPUB() {
        let books = model.selectedBooks
        Task {
            if await onExportBooksAsEPUB(books) {
                model.endBookSelection()
            }
        }
    }

    private func exportSelectedBooksAsMarkdown() {
        let books = model.selectedBooks
        Task {
            if await onExportBooksAsMarkdown(books) {
                model.endBookSelection()
            }
        }
    }

    private var batchConfirmationTitle: String {
        batchConfirmation?.title ?? "Confirm Library Operation"
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

private enum LibraryBatchConfirmation: Identifiable {
    case moveToTrash([UUID])
    case clearReadingProgress([UUID])
    case emptyTrash(Int)

    var id: String {
        switch self {
        case .moveToTrash:
            "move-to-trash"
        case .clearReadingProgress:
            "clear-reading-progress"
        case .emptyTrash:
            "empty-trash"
        }
    }

    var title: String {
        switch self {
        case .moveToTrash(let bookIDs):
            let count = bookIDs.count
            return "Move \(count) \(count == 1 ? "Book" : "Books") to Trash?"
        case .clearReadingProgress(let bookIDs):
            let count = bookIDs.count
            return "Clear Reading Progress for \(count) \(count == 1 ? "Book" : "Books")?"
        case .emptyTrash:
            return "Empty Trash?"
        }
    }

    var message: String {
        switch self {
        case .moveToTrash:
            "The selected books can be restored from Trash."
        case .clearReadingProgress:
            "The selected books will leave Currently Reading. Bookmarks and Recently Opened history will be preserved."
        case .emptyTrash(let count):
            "This permanently deletes all \(count) \(count == 1 ? "book" : "books") in Trash and cannot be undone."
        }
    }
}
