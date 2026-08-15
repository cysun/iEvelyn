import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    let books: [LibraryBook]
    let referenceDate: Date

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

    init(books: [LibraryBook]? = nil, referenceDate: Date = .now) {
        self.referenceDate = referenceDate
        self.books = books ?? SampleLibrary.books(referenceDate: referenceDate)
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

    private func reconcileSelection() {
        guard let selectedBookID else { return }
        if !visibleBooks.contains(where: { $0.id == selectedBookID }) {
            self.selectedBookID = nil
        }
    }
}
