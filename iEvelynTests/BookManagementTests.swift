import Foundation
import GRDB
import Testing
@testable import iEvelyn

@Suite("Book management", .serialized)
struct BookManagementTests {
    private let createdAt = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("Create and update persist normalized metadata and ordered authors")
    func createAndUpdateMetadata() async throws {
        let repository = try makeRepository()
        let bookID = try await repository.createBook(
            metadata: BookMetadataInput(
                title: "  The Test Book  ",
                subtitle: "  A Durable Subtitle ",
                authors: [" First Author ", "Second Author"],
                summary: "  A useful summary.  "
            ),
            at: createdAt
        )

        let inserted = try #require(await repository.fetchBook(id: bookID))
        #expect(inserted.title == "The Test Book")
        #expect(inserted.subtitle == "A Durable Subtitle")
        #expect(inserted.summary == "A useful summary.")
        #expect(inserted.createdAt == createdAt)
        #expect(inserted.updatedAt == createdAt)
        #expect(inserted.lastOpenedAt == nil)
        #expect(try await repository.authors(forBookID: bookID).map(\.displayName) == [
            "First Author",
            "Second Author"
        ])

        let updatedAt = createdAt.addingTimeInterval(120)
        try await repository.updateBook(
            id: bookID,
            metadata: BookMetadataInput(
                title: "Revised Book",
                authors: ["Second Author", "Third Author"],
                summary: "Revised summary"
            ),
            at: updatedAt
        )

        let updated = try #require(await repository.fetchBook(id: bookID))
        #expect(updated.title == "Revised Book")
        #expect(updated.subtitle == nil)
        #expect(updated.summary == "Revised summary")
        #expect(updated.createdAt == createdAt)
        #expect(updated.updatedAt == updatedAt)
        #expect(updated.lastOpenedAt == nil)
        #expect(try await repository.authors(forBookID: bookID).map(\.displayName) == [
            "Second Author",
            "Third Author"
        ])
    }

    @Test("Validation rejects incomplete and ambiguous metadata")
    func validationRejectsInvalidMetadata() {
        expectValidationError(.titleRequired) {
            try BookMetadataInput(title: "  ", authors: ["Author"]).validated()
        }
        expectValidationError(.authorRequired) {
            try BookMetadataInput(title: "Book", authors: [""]).validated()
        }
        expectValidationError(.duplicateAuthor("ELODIE")) {
            try BookMetadataInput(
                title: "Book",
                authors: ["Élodie", "ELODIE"]
            ).validated()
        }
    }

    @Test("Favorite, opened, Trash, restore, filtering, and permanent deletion are consistent")
    func lifecycleOperationsAreConsistent() async throws {
        let repository = try makeRepository()
        let bookID = try await repository.createBook(
            metadata: BookMetadataInput(title: "Lifecycle", authors: ["Test Author"]),
            at: createdAt
        )

        let favoritedAt = createdAt.addingTimeInterval(10)
        try await repository.setFavorite(bookID: bookID, isFavorite: true, at: favoritedAt)
        var book = try #require(await repository.fetchBook(id: bookID))
        #expect(book.isFavorite)
        #expect(book.updatedAt == favoritedAt)

        let openedAt = createdAt.addingTimeInterval(20)
        try await repository.markBookOpened(id: bookID, at: openedAt)
        book = try #require(await repository.fetchBook(id: bookID))
        #expect(book.lastOpenedAt == openedAt)
        #expect(book.updatedAt == favoritedAt)

        var projection = try await repository.fetchLibraryBooks()
        #expect(query(.favorites, projection).map(\.id) == [bookID])
        #expect(query(.allBooks, projection).map(\.id) == [bookID])

        let trashedAt = createdAt.addingTimeInterval(30)
        try await repository.moveBookToTrash(id: bookID, at: trashedAt)
        projection = try await repository.fetchLibraryBooks()
        #expect(query(.allBooks, projection).isEmpty)
        #expect(query(.favorites, projection).isEmpty)
        #expect(query(.trash, projection).map(\.id) == [bookID])

        let restoredAt = createdAt.addingTimeInterval(40)
        try await repository.restoreBook(id: bookID, at: restoredAt)
        book = try #require(await repository.fetchBook(id: bookID))
        #expect(book.trashedAt == nil)
        #expect(book.updatedAt == restoredAt)

        await expectRepositoryError(.permanentDeleteRequiresTrash) {
            try await repository.deleteBookPermanently(id: bookID)
        }

        try await repository.moveBookToTrash(
            id: bookID,
            at: createdAt.addingTimeInterval(50)
        )
        try await repository.deleteBookPermanently(id: bookID)
        #expect(try await repository.fetchBook(id: bookID) == nil)
        #expect(try await repository.fetchLibraryBooks().isEmpty)
    }

    @Test("Batch Trash operations validate atomically and Empty Trash deletes every trashed book")
    func batchTrashAndEmptyTrashAreAtomic() async throws {
        let repository = try makeRepository()
        let firstID = try await repository.createBook(
            metadata: BookMetadataInput(title: "First", authors: ["Author"]),
            at: createdAt
        )
        let secondID = try await repository.createBook(
            metadata: BookMetadataInput(title: "Second", authors: ["Author"]),
            at: createdAt
        )
        let activeID = try await repository.createBook(
            metadata: BookMetadataInput(title: "Active", authors: ["Author"]),
            at: createdAt
        )
        let trashedAt = createdAt.addingTimeInterval(30)

        try await repository.moveBooksToTrash(
            ids: [secondID, firstID, secondID],
            at: trashedAt
        )
        var books = try await repository.fetchLibraryBooks()
        #expect(Set(books.filter(\.isTrashed).map(\.id)) == [firstID, secondID])
        #expect(books.first(where: { $0.id == activeID })?.isTrashed == false)

        await expectRepositoryError(.bookNotFound) {
            try await repository.moveBooksToTrash(
                ids: [activeID, UUID()],
                at: trashedAt.addingTimeInterval(1)
            )
        }
        #expect(try await repository.fetchBook(id: activeID)?.trashedAt == nil)

        #expect(try await repository.emptyTrash() == 2)
        books = try await repository.fetchLibraryBooks()
        #expect(books.map(\.id) == [activeID])
        #expect(try await repository.emptyTrash() == 0)
    }

    @MainActor
    @Test("Selection mode selects the visible collection and resets across destinations")
    func selectionModeTracksVisibleBooks() {
        let first = makeLibraryBook(title: "Alpha")
        let second = makeLibraryBook(title: "Beta")
        let third = makeLibraryBook(title: "Gamma")
        let model = LibraryViewModel(
            repository: ReadOnlyBookRepository(books: [first, second, third]),
            initialBooks: [first, second, third],
            referenceDate: createdAt
        )

        model.beginBookSelection()
        #expect(model.isSelectingBooks)
        #expect(model.selectedBooks.isEmpty)

        model.toggleBookSelection(second)
        #expect(model.selectedBooks.map(\.id) == [second.id])
        model.toggleSelectAllVisibleBooks()
        #expect(model.areAllVisibleBooksSelected)
        #expect(Set(model.selectedBooks.map(\.id)) == [first.id, second.id, third.id])

        model.toggleSelectAllVisibleBooks()
        #expect(model.selectedBooks.isEmpty)
        model.toggleBookSelection(first)
        model.destination = .favorites
        #expect(!model.isSelectingBooks)
        #expect(model.selectedBooks.isEmpty)
    }

    @MainActor
    @Test("Feature operation failures are surfaced as actionable alerts")
    func operationFailuresAreSurfaced() async {
        let book = makeLibraryBook()
        let model = LibraryViewModel(
            repository: ReadOnlyBookRepository(books: [book]),
            initialBooks: [book],
            referenceDate: createdAt,
            now: { Date(timeIntervalSince1970: 2_000_000_100) }
        )

        await model.toggleFavorite(for: book)

        #expect(model.alert?.title == "Could Not Update Favorite")
        #expect(model.alert?.message == LibraryRepositoryError.readOnlyRepository.localizedDescription)
        #expect(!model.isPerformingOperation)
    }

    private func makeRepository() throws -> GRDBLibraryRepository {
        GRDBLibraryRepository(database: try LibraryDatabase.makeInMemory())
    }

    private func query(_ destination: LibraryDestination, _ books: [LibraryBook]) -> [LibraryBook] {
        LibraryQuery(
            destination: destination,
            searchText: "",
            sortOrder: .title,
            referenceDate: createdAt
        ).apply(to: books)
    }

    private func makeLibraryBook(title: String = "Read Only") -> LibraryBook {
        LibraryBook(
            id: UUID(),
            title: title,
            subtitle: nil,
            authors: ["Test Author"],
            summary: "",
            tags: [],
            dateAdded: createdAt,
            isFavorite: false,
            isCurrentlyReading: false,
            readingProgress: nil,
            isTrashed: false,
            coverStyle: .slate
        )
    }

    private func expectValidationError(
        _ expectedError: BookMetadataValidationError,
        operation: () throws -> ValidatedBookMetadata,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            _ = try operation()
            Issue.record("Expected validation to fail", sourceLocation: sourceLocation)
        } catch let error as BookMetadataValidationError {
            #expect(error == expectedError, sourceLocation: sourceLocation)
        } catch {
            Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation)
        }
    }

    private func expectRepositoryError(
        _ expectedError: LibraryRepositoryError,
        operation: () async throws -> Void,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        do {
            try await operation()
            Issue.record("Expected repository operation to fail", sourceLocation: sourceLocation)
        } catch let error as LibraryRepositoryError {
            #expect(error == expectedError, sourceLocation: sourceLocation)
        } catch {
            Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation)
        }
    }
}

private nonisolated struct ReadOnlyBookRepository: LibraryRepository, Sendable {
    let books: [LibraryBook]

    func observeLibraryBooks() -> AsyncThrowingStream<[LibraryBook], Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(books)
            continuation.finish()
        }
    }
}
