import Foundation
import GRDB
import Testing
@testable import iEvelyn

@Suite("Reading progress and bookmarks", .serialized)
struct ReadingProgressBookmarkTests {
    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Newest progress wins and updates the library projection atomically")
    func newestProgressWins() async throws {
        let repository = try makeRepository()
        let (bookID, chapters) = try await createBook(in: repository)
        let newerDate = referenceDate.addingTimeInterval(20)
        let newerProgress = ReadingProgress(
            bookID: bookID,
            chapterID: chapters[1].id,
            stableBlockID: "saved-block",
            textQuote: "Saved paragraph",
            contextBefore: "Before",
            contextAfter: "After",
            fractionInChapter: 0.5,
            overallProgress: 0.75,
            lastReadAt: newerDate
        )
        try await repository.saveReadingProgress(newerProgress)

        try await repository.saveReadingProgress(
            ReadingProgress(
                bookID: bookID,
                chapterID: chapters[0].id,
                stableBlockID: "stale-block",
                textQuote: "Stale",
                contextBefore: nil,
                contextAfter: nil,
                fractionInChapter: 0.1,
                overallProgress: 0.05,
                lastReadAt: referenceDate.addingTimeInterval(10)
            )
        )

        #expect(try await repository.readingProgress(forBookID: bookID) == newerProgress)
        let projectedBook = try #require(await repository.fetchLibraryBooks().first)
        #expect(projectedBook.isCurrentlyReading)
        #expect(projectedBook.readingProgress == 0.75)
        #expect(projectedBook.lastOpenedAt == newerDate)
    }

    @Test("Bookmark observation supports unlabeled create and delete without notes")
    func bookmarkCRUD() async throws {
        let repository = try makeRepository()
        let (bookID, chapters) = try await createBook(in: repository)
        var values = repository.observeBookmarks(forBookID: bookID).makeAsyncIterator()
        #expect(try await values.next() == [])

        let bookmark = Bookmark(
            bookID: bookID,
            chapterID: chapters[0].id,
            stableBlockID: "saved-block",
            textQuote: "Saved paragraph",
            fractionInChapter: 0.25,
            label: "  Return here  ",
            note: "Notes are outside the current product scope",
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
        try await repository.createBookmark(bookmark)
        let created = try #require(try await values.next()).first
        #expect(created?.id == bookmark.id)
        #expect(created?.label == nil)
        #expect(created?.note == nil)

        try await repository.deleteBookmark(id: bookmark.id, bookID: bookID)
        #expect(try await values.next() == [])
    }

    @Test("Currently Reading can order books by the latest saved reading time")
    func currentlyReadingOrder() async throws {
        let repository = try makeRepository()
        let (olderBookID, olderChapters) = try await createBook(in: repository)
        let (newerBookID, newerChapters) = try await createBook(in: repository)

        try await repository.saveReadingProgress(
            ReadingProgress(
                bookID: olderBookID,
                chapterID: olderChapters[0].id,
                fractionInChapter: 0.2,
                overallProgress: 0.1,
                lastReadAt: referenceDate.addingTimeInterval(10)
            )
        )
        try await repository.saveReadingProgress(
            ReadingProgress(
                bookID: newerBookID,
                chapterID: newerChapters[1].id,
                fractionInChapter: 0.4,
                overallProgress: 0.7,
                lastReadAt: referenceDate.addingTimeInterval(20)
            )
        )

        let orderedIDs = LibraryQuery(
            destination: .currentlyReading,
            searchText: "",
            sortOrder: .recentlyOpened,
            referenceDate: referenceDate
        )
        .apply(to: try await repository.fetchLibraryBooks())
        .map(\.id)
        #expect(orderedIDs == [newerBookID, olderBookID])
    }

    @Test("Append preserves anchors and replacement retains graceful book-level fallback")
    func anchorsAcrossWholeBookUpdates() async throws {
        let repository = try makeRepository()
        let (bookID, originalChapters) = try await createBook(in: repository)
        let progress = ReadingProgress(
            bookID: bookID,
            chapterID: originalChapters[1].id,
            stableBlockID: "saved-block",
            textQuote: "Saved paragraph",
            contextBefore: "Before",
            contextAfter: "After",
            fractionInChapter: 0.4,
            overallProgress: 0.7,
            lastReadAt: referenceDate
        )
        let bookmark = Bookmark(
            bookID: bookID,
            chapterID: originalChapters[1].id,
            stableBlockID: "saved-block",
            textQuote: "Saved paragraph",
            contextBefore: "Before",
            contextAfter: "After",
            fractionInChapter: 0.4,
            label: nil,
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
        try await repository.saveReadingProgress(progress)
        try await repository.createBookmark(bookmark)

        try await repository.updateBook(
            id: bookID,
            metadata: BookMetadataInput(title: "Reading Book", authors: ["Reader"]),
            chapterUpdate: .append([
                ImportedBookChapter(title: "Appendix", markdown: "## Appendix\n\nExtra.")
            ]),
            coverUpdate: .unchanged,
            at: referenceDate.addingTimeInterval(1)
        )
        #expect(try await repository.readingProgress(forBookID: bookID)?.chapterID == originalChapters[1].id)
        #expect(try await storedBookmark(bookmark.id, repository: repository)?.chapterID == originalChapters[1].id)

        try await repository.updateBook(
            id: bookID,
            metadata: BookMetadataInput(title: "Reading Book", authors: ["Reader"]),
            chapterUpdate: .replace([
                ImportedBookChapter(title: "Opening", markdown: "## Opening\n\nChanged.")
            ]),
            coverUpdate: .unchanged,
            at: referenceDate.addingTimeInterval(2)
        )

        let detachedProgress = try #require(await repository.readingProgress(forBookID: bookID))
        #expect(detachedProgress.chapterID == nil)
        #expect(detachedProgress.stableBlockID == "saved-block")
        #expect(detachedProgress.textQuote == "Saved paragraph")
        let detachedBookmark = try #require(await storedBookmark(bookmark.id, repository: repository))
        #expect(detachedBookmark.chapterID == nil)
        #expect(detachedBookmark.stableBlockID == "saved-block")
        #expect(detachedBookmark.note == nil)
    }

    private func makeRepository() throws -> GRDBLibraryRepository {
        GRDBLibraryRepository(database: try LibraryDatabase.makeInMemory())
    }

    private func createBook(
        in repository: GRDBLibraryRepository
    ) async throws -> (UUID, [Chapter]) {
        let bookID = try await repository.createBook(
            metadata: BookMetadataInput(title: "Reading Book", authors: ["Reader"]),
            contentChapters: [
                ImportedBookChapter(title: "Opening", markdown: "## Opening\n\nFirst."),
                ImportedBookChapter(title: "Ending", markdown: "## Ending\n\nLast."),
            ],
            coverSourceURL: nil,
            at: referenceDate
        )
        return (bookID, try await repository.chapters(forBookID: bookID))
    }

    private func storedBookmark(
        _ id: UUID,
        repository: GRDBLibraryRepository
    ) async throws -> Bookmark? {
        try await repository.database.read { database in
            try Bookmark.fetchOne(database, key: id.databaseString)
        }
    }
}
