import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    private let repository: any LibraryRepository
    let referenceDate: Date
    private(set) var books: [LibraryBook]
    private(set) var isLoading: Bool
    private(set) var errorMessage: String?
    private(set) var isPerformingOperation = false
    var alert: LibraryViewModelAlert?
    private var isObserving = false
    private let now: @Sendable () -> Date

    var destination: LibraryDestination = .allBooks {
        didSet { reconcileSelection() }
    }

    var presentation: LibraryPresentation = .grid

    var sortOrder: LibrarySortOrder = .title {
        didSet { reconcileSelection() }
    }

    var searchText = "" {
        didSet { reconcileSelection() }
    }

    var selectedBookID: LibraryBook.ID?

    init(
        repository: any LibraryRepository,
        initialBooks: [LibraryBook] = [],
        referenceDate: Date = .now,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.repository = repository
        self.referenceDate = referenceDate
        self.now = now
        books = initialBooks
        isLoading = initialBooks.isEmpty
    }

    var visibleBooks: [LibraryBook] {
        LibraryQuery(
            destination: destination,
            searchText: searchText,
            sortOrder: sortOrder,
            referenceDate: referenceDate
        )
        .apply(to: books)
    }

    var selectedBook: LibraryBook? {
        guard let selectedBookID else { return nil }
        return books.first { $0.id == selectedBookID }
    }

    func clearSearch() {
        searchText = ""
    }

    @discardableResult
    func saveBook(id: UUID?, metadata: BookMetadataInput) async throws -> UUID {
        let bookID: UUID
        if let id {
            try await repository.updateBook(id: id, metadata: metadata, at: now())
            bookID = id
        } else {
            bookID = try await repository.createBook(metadata: metadata, at: now())
        }

        destination = .allBooks
        selectedBookID = bookID
        return bookID
    }

    func toggleFavorite(for book: LibraryBook) async {
        await performOperation(errorTitle: "Could Not Update Favorite") {
            try await repository.setFavorite(
                bookID: book.id,
                isFavorite: !book.isFavorite,
                at: now()
            )
        }
    }

    func moveToTrash(_ book: LibraryBook) async {
        let succeeded = await performOperation(errorTitle: "Could Not Move Book to Trash") {
            try await repository.moveBookToTrash(id: book.id, at: now())
        }
        if succeeded {
            selectedBookID = nil
        }
    }

    func restore(_ book: LibraryBook) async {
        let succeeded = await performOperation(errorTitle: "Could Not Restore Book") {
            try await repository.restoreBook(id: book.id, at: now())
        }
        if succeeded {
            selectedBookID = nil
        }
    }

    func permanentlyDelete(_ book: LibraryBook) async {
        let succeeded = await performOperation(errorTitle: "Could Not Delete Book") {
            try await repository.deleteBookPermanently(id: book.id)
        }
        if succeeded {
            selectedBookID = nil
        }
    }

    func markOpened(_ book: LibraryBook) async {
        guard !book.isTrashed else { return }
        do {
            try await repository.markBookOpened(id: book.id, at: now())
        } catch is CancellationError {
            return
        } catch {
            alert = LibraryViewModelAlert(
                title: "Could Not Update Recently Opened",
                message: error.localizedDescription
            )
        }
    }

    func observeLibrary() async {
        guard !isObserving else { return }
        isObserving = true
        isLoading = books.isEmpty
        errorMessage = nil
        defer { isObserving = false }

        do {
            for try await observedBooks in repository.observeLibraryBooks() {
                books = observedBooks
                isLoading = false
                errorMessage = nil
                reconcileSelection()
            }
        } catch is CancellationError {
            return
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    private func reconcileSelection() {
        guard let selectedBookID else { return }
        if !visibleBooks.contains(where: { $0.id == selectedBookID }) {
            self.selectedBookID = nil
        }
    }

    @discardableResult
    private func performOperation(
        errorTitle: String,
        operation: () async throws -> Void
    ) async -> Bool {
        guard !isPerformingOperation else { return false }
        isPerformingOperation = true
        defer { isPerformingOperation = false }

        do {
            try await operation()
            return true
        } catch is CancellationError {
            return false
        } catch {
            alert = LibraryViewModelAlert(
                title: errorTitle,
                message: error.localizedDescription
            )
            return false
        }
    }
}

nonisolated struct LibraryViewModelAlert: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let message: String
}
