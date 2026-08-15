import Foundation
import Testing
@testable import iEvelyn

@Suite("Library query behavior")
struct LibraryQueryTests {
    private let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("Destinations include only their matching books")
    func destinationsFilterBooks() {
        let books = fixtureBooks

        #expect(ids(for: .allBooks, in: books) == ["active", "old"])
        #expect(ids(for: .currentlyReading, in: books) == ["active"])
        #expect(ids(for: .recentlyAdded, in: books) == ["active"])
        #expect(ids(for: .favorites, in: books) == ["old"])
        #expect(ids(for: .trash, in: books) == ["trashed"])
    }

    @Test("Search matches title, author, subtitle, and tags without case sensitivity")
    func searchMatchesVisibleMetadata() {
        let books = fixtureBooks

        #expect(ids(searching: "  OCTAVIA  ", in: books) == ["active"])
        #expect(ids(searching: "Ambiguous", in: books) == ["old"])
        #expect(ids(searching: "classic", in: books) == ["old"])
        #expect(ids(searching: "not present", in: books).isEmpty)
    }

    @Test("Sort orders are deterministic")
    func sortOrdersAreDeterministic() {
        let books = fixtureBooks

        #expect(ids(sortedBy: .title, in: books) == ["old", "active"])
        #expect(ids(sortedBy: .author, in: books) == ["active", "old"])
        #expect(ids(sortedBy: .recentlyAdded, in: books) == ["active", "old"])
    }

    @Test("Sample data is stable and internally valid")
    func sampleDataIsStableAndValid() {
        let books = SampleLibrary.books(referenceDate: referenceDate)

        #expect(books.count == 8)
        #expect(Set(books.map(\.id)).count == books.count)
        #expect(books.allSatisfy { !$0.title.isEmpty && !$0.authors.isEmpty })
        #expect(books.allSatisfy { !$0.isTrashed })

        let recentIDs = ids(for: .recentlyAdded, in: books)
        #expect(recentIDs == ["kindred", "piranesi", "psalm-for-the-wild-built"])
    }

    @MainActor
    @Test("Window models keep transient selection independent")
    func windowModelsKeepSelectionIndependent() {
        let books = SampleLibrary.books(referenceDate: referenceDate)
        guard let firstBook = books.first else {
            Issue.record("SampleLibrary should provide at least one book")
            return
        }

        let firstWindow = LibraryViewModel(books: books, referenceDate: referenceDate)
        let secondWindow = LibraryViewModel(books: books, referenceDate: referenceDate)

        firstWindow.selectedBookID = firstBook.id

        #expect(firstWindow.selectedBookID == firstBook.id)
        #expect(secondWindow.selectedBookID == nil)

        firstWindow.destination = .trash
        #expect(firstWindow.selectedBookID == nil)
    }

    private var fixtureBooks: [LibraryBook] {
        [
            makeBook(
                id: "active",
                title: "Kindred",
                subtitle: nil,
                author: "Octavia E. Butler",
                tags: ["Time Travel"],
                daysBefore: 5,
                isFavorite: false,
                isCurrentlyReading: true,
                isTrashed: false
            ),
            makeBook(
                id: "old",
                title: "An Ambiguous Utopia",
                subtitle: "The Dispossessed",
                author: "Ursula K. Le Guin",
                tags: ["Classic"],
                daysBefore: 45,
                isFavorite: true,
                isCurrentlyReading: false,
                isTrashed: false
            ),
            makeBook(
                id: "trashed",
                title: "Archived Draft",
                subtitle: nil,
                author: "A. Writer",
                tags: ["Draft"],
                daysBefore: 1,
                isFavorite: true,
                isCurrentlyReading: true,
                isTrashed: true
            )
        ]
    }

    private func makeBook(
        id: String,
        title: String,
        subtitle: String?,
        author: String,
        tags: [String],
        daysBefore: Int,
        isFavorite: Bool,
        isCurrentlyReading: Bool,
        isTrashed: Bool
    ) -> LibraryBook {
        let calendar = Calendar(identifier: .gregorian)
        let dateAdded = calendar.date(byAdding: .day, value: -daysBefore, to: referenceDate) ?? referenceDate

        return LibraryBook(
            id: id,
            title: title,
            subtitle: subtitle,
            authors: [author],
            summary: "Fixture summary",
            tags: tags,
            dateAdded: dateAdded,
            isFavorite: isFavorite,
            isCurrentlyReading: isCurrentlyReading,
            readingProgress: isCurrentlyReading ? 0.5 : nil,
            isTrashed: isTrashed,
            coverStyle: .slate
        )
    }

    private func ids(
        for destination: LibraryDestination = .allBooks,
        in books: [LibraryBook]
    ) -> [LibraryBook.ID] {
        LibraryQuery(
            destination: destination,
            searchText: "",
            sortOrder: .recentlyAdded,
            referenceDate: referenceDate
        )
        .apply(to: books)
        .map(\.id)
    }

    private func ids(searching searchText: String, in books: [LibraryBook]) -> [LibraryBook.ID] {
        LibraryQuery(
            destination: .allBooks,
            searchText: searchText,
            sortOrder: .title,
            referenceDate: referenceDate
        )
        .apply(to: books)
        .map(\.id)
    }

    private func ids(sortedBy sortOrder: LibrarySortOrder, in books: [LibraryBook]) -> [LibraryBook.ID] {
        LibraryQuery(
            destination: .allBooks,
            searchText: "",
            sortOrder: sortOrder,
            referenceDate: referenceDate
        )
        .apply(to: books)
        .map(\.id)
    }
}
