import Foundation
import Testing
@testable import iEvelyn

@Suite("Library query behavior")
struct LibraryQueryTests {
    private let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("Destinations include only their matching books")
    func destinationsFilterBooks() {
        let books = fixtureBooks

        #expect(ids(for: .allBooks, in: books) == [FixtureID.active, FixtureID.old])
        #expect(ids(for: .currentlyReading, in: books) == [FixtureID.active])
        #expect(ids(for: .recentlyAdded, in: books) == [FixtureID.active])
        #expect(ids(for: .favorites, in: books) == [FixtureID.old])
        #expect(ids(for: .trash, in: books) == [FixtureID.trashed])
    }

    @Test("Search matches title, author, subtitle, and tags without case sensitivity")
    func searchMatchesVisibleMetadata() {
        let books = fixtureBooks

        #expect(ids(searching: "  OCTAVIA  ", in: books) == [FixtureID.active])
        #expect(ids(searching: "Ambiguous", in: books) == [FixtureID.old])
        #expect(ids(searching: "classic", in: books) == [FixtureID.old])
        #expect(ids(searching: "not present", in: books).isEmpty)
    }

    @Test("Sort orders are deterministic")
    func sortOrdersAreDeterministic() {
        let books = fixtureBooks

        #expect(ids(sortedBy: .title, in: books) == [FixtureID.old, FixtureID.active])
        #expect(ids(sortedBy: .author, in: books) == [FixtureID.active, FixtureID.old])
        #expect(ids(sortedBy: .recentlyAdded, in: books) == [FixtureID.active, FixtureID.old])
    }

    @Test("Recently opened sorting puts never-opened books last")
    func recentlyOpenedSortUsesPersistedTimestamps() {
        let books = [
            makeBook(
                id: FixtureID.active,
                title: "Opened Earlier",
                subtitle: nil,
                author: "A. Author",
                tags: [],
                daysBefore: 5,
                isFavorite: false,
                isCurrentlyReading: false,
                isTrashed: false,
                lastOpenedDaysBefore: 3
            ),
            makeBook(
                id: FixtureID.old,
                title: "Opened Latest",
                subtitle: nil,
                author: "B. Author",
                tags: [],
                daysBefore: 10,
                isFavorite: false,
                isCurrentlyReading: false,
                isTrashed: false,
                lastOpenedDaysBefore: 1
            ),
            makeBook(
                id: FixtureID.trashed,
                title: "Never Opened",
                subtitle: nil,
                author: "C. Author",
                tags: [],
                daysBefore: 1,
                isFavorite: false,
                isCurrentlyReading: false,
                isTrashed: false
            )
        ]

        #expect(ids(sortedBy: .recentlyOpened, in: books) == [
            FixtureID.old,
            FixtureID.active,
            FixtureID.trashed
        ])
    }

    @Test("Sample data is stable and internally valid")
    func sampleDataIsStableAndValid() {
        let books = SampleLibrary.previewBooks(referenceDate: referenceDate)

        #expect(books.count == 8)
        #expect(Set(books.map(\.id)).count == books.count)
        #expect(books.allSatisfy { !$0.title.isEmpty && !$0.authors.isEmpty })
        #expect(books.allSatisfy { !$0.isTrashed })

        let recentTitles = LibraryQuery(
            destination: .recentlyAdded,
            searchText: "",
            sortOrder: .recentlyAdded,
            referenceDate: referenceDate
        )
        .apply(to: books)
        .map(\.title)
        #expect(recentTitles == ["Kindred", "Piranesi", "A Psalm for the Wild-Built"])
    }

    @MainActor
    @Test("Window models keep transient browsing state independent")
    func windowModelsKeepBrowsingStateIndependent() {
        let books = SampleLibrary.previewBooks(referenceDate: referenceDate)
        let repository = PreviewLibraryRepository(books: books)
        let firstWindow = LibraryViewModel(
            repository: repository,
            initialBooks: books,
            referenceDate: referenceDate
        )
        let secondWindow = LibraryViewModel(
            repository: repository,
            initialBooks: books,
            referenceDate: referenceDate
        )

        firstWindow.presentation = .list
        firstWindow.searchText = "Kindred"

        #expect(firstWindow.presentation == .list)
        #expect(firstWindow.searchText == "Kindred")
        #expect(secondWindow.presentation == .grid)
        #expect(secondWindow.searchText.isEmpty)
    }

    private var fixtureBooks: [LibraryBook] {
        [
            makeBook(
                id: FixtureID.active,
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
                id: FixtureID.old,
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
                id: FixtureID.trashed,
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
        id: UUID,
        title: String,
        subtitle: String?,
        author: String,
        tags: [String],
        daysBefore: Int,
        isFavorite: Bool,
        isCurrentlyReading: Bool,
        isTrashed: Bool,
        lastOpenedDaysBefore: Int? = nil
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
            coverStyle: .slate,
            lastOpenedAt: lastOpenedDaysBefore.flatMap {
                calendar.date(byAdding: .day, value: -$0, to: referenceDate)
            }
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

private nonisolated enum FixtureID {
    static let active = UUID(uuid: (0x10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    static let old = UUID(uuid: (0x20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
    static let trashed = UUID(uuid: (0x30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3))
}
