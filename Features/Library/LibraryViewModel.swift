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
    private var isObserving = false

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
        referenceDate: Date = .now
    ) {
        self.repository = repository
        self.referenceDate = referenceDate
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

    func observeLibrary() async {
        guard !isObserving else { return }
        isObserving = true
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
}
