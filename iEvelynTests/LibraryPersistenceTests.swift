import Foundation
import GRDB
import Testing
@testable import iEvelyn

@Suite("Library persistence", .serialized)
struct LibraryPersistenceTests {
    private let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("Migration creates every normalized table from version zero")
    func migrationCreatesSchemaFromVersionZero() async throws {
        let database = try LibraryDatabase.makeInMemory()
        let diagnostics = try await database.diagnostics()
        let tables = try await database.read { database in
            try String.fetchAll(
                database,
                sql: """
                    SELECT name FROM sqlite_master
                    WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'
                    ORDER BY name
                    """
            )
        }

        #expect(diagnostics.location == .inMemory)
        #expect(diagnostics.foreignKeysEnabled)
        #expect(diagnostics.journalMode == "memory")
        #expect(diagnostics.appliedMigrations == [LibrarySchema.initialMigrationIdentifier])
        #expect(tables == [
            "assets",
            "authors",
            "bookAuthors",
            "bookTags",
            "bookmarks",
            "books",
            "chapters",
            "readingProgress",
            "tags"
        ])
    }

    @Test("Disk databases use WAL and survive reopening")
    func diskDatabaseUsesWALAndSurvivesReopening() async throws {
        let directoryURL = temporaryDirectory(named: "reopen")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let book = makeBook(title: "Persistent Book")
        do {
            let database = try LibraryDatabase.makeTemporary(in: directoryURL)
            let repository = GRDBLibraryRepository(database: database)
            try await repository.insertBook(book)

            let diagnostics = try await database.diagnostics()
            #expect(diagnostics.journalMode == "wal")
            #expect(diagnostics.foreignKeysEnabled)
        }

        do {
            let reopenedDatabase = try LibraryDatabase.makeTemporary(in: directoryURL)
            let reopenedRepository = GRDBLibraryRepository(database: reopenedDatabase)
            #expect(try await reopenedRepository.fetchBook(id: book.id) == book)
        }

        try FileManager.default.removeItem(at: directoryURL)
    }

    @Test("CRUD covers every initial entity and assembles the library projection")
    func crudCoversInitialEntities() async throws {
        let repository = try makeRepository()
        let book = makeBook(title: "A Durable Library", favorite: true)
        try await repository.insertBook(book)

        var updatedBook = book
        updatedBook.subtitle = "A Persistence Test"
        updatedBook.updatedAt = referenceDate.addingTimeInterval(60)
        try await repository.updateBook(updatedBook)
        #expect(try await repository.fetchBook(id: book.id) == updatedBook)

        let firstAuthor = Author(displayName: "Second Author", createdAt: referenceDate, updatedAt: referenceDate)
        let secondAuthor = Author(displayName: "First Author", createdAt: referenceDate, updatedAt: referenceDate)
        try await repository.insertAuthor(firstAuthor)
        try await repository.insertAuthor(secondAuthor)
        try await repository.linkAuthor(BookAuthor(bookID: book.id, authorID: firstAuthor.id, position: 1))
        try await repository.linkAuthor(BookAuthor(bookID: book.id, authorID: secondAuthor.id, position: 0))

        let chapter = Chapter(
            bookID: book.id,
            title: "Opening",
            markdown: "Canonical Markdown",
            position: 0,
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
        try await repository.insertChapter(chapter)

        let tag = Tag(name: "Reference", createdAt: referenceDate, updatedAt: referenceDate)
        try await repository.insertTag(tag)
        try await repository.linkTag(BookTag(bookID: book.id, tagID: tag.id))

        let asset = Asset(
            bookID: book.id,
            chapterID: chapter.id,
            purpose: .chapterImage,
            mediaType: "image/png",
            storageRelativePath: "Books/\(book.id)/image.png",
            checksum: "abc123",
            byteCount: 42,
            pixelWidth: 10,
            pixelHeight: 20,
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
        try await repository.insertAsset(asset)

        try await repository.insertReadingProgress(
            ReadingProgress(
                bookID: book.id,
                chapterID: chapter.id,
                stableBlockID: "opening-p1",
                textQuote: "Canonical",
                contextBefore: nil,
                contextAfter: "Markdown",
                fractionInChapter: 0.25,
                overallProgress: 0.2,
                lastReadAt: referenceDate
            )
        )

        let bookmark = Bookmark(
            bookID: book.id,
            chapterID: chapter.id,
            stableBlockID: "opening-p1",
            textQuote: "Canonical",
            fractionInChapter: 0.25,
            label: "Start here",
            note: "Fixture note",
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
        try await repository.insertBookmark(bookmark)

        let projection = try await repository.fetchLibraryBooks()
        let counts = try await entityCounts(repository.database)

        #expect(projection.count == 1)
        #expect(projection.first?.id == book.id)
        #expect(projection.first?.authors == ["First Author", "Second Author"])
        #expect(projection.first?.tags == ["Reference"])
        #expect(projection.first?.readingProgress == 0.2)
        #expect(counts == EntityCounts(
            books: 1,
            authors: 2,
            bookAuthors: 2,
            chapters: 1,
            assets: 1,
            tags: 1,
            bookTags: 1,
            readingProgress: 1,
            bookmarks: 1
        ))
    }

    @Test("Constraints reject invalid values and cross-book chapter anchors")
    func constraintsRejectInvalidValues() async throws {
        let repository = try makeRepository()
        await expectFailure {
            try await repository.insertBook(makeBook(title: "   "))
        }

        let firstBook = makeBook(title: "First")
        let secondBook = makeBook(title: "Second")
        try await repository.insertBook(firstBook)
        try await repository.insertBook(secondBook)

        let firstAuthor = Author(displayName: "Élodie Writer")
        let duplicateAuthor = Author(displayName: "elodie writer")
        try await repository.insertAuthor(firstAuthor)
        await expectFailure {
            try await repository.insertAuthor(duplicateAuthor)
        }

        let chapter = Chapter(bookID: firstBook.id, title: "One", position: 0)
        try await repository.insertChapter(chapter)
        let mismatchedAsset = Asset(
            bookID: secondBook.id,
            chapterID: chapter.id,
            purpose: .chapterImage,
            mediaType: "image/png",
            storageRelativePath: "mismatch.png",
            checksum: "checksum",
            byteCount: 1
        )
        await expectFailure {
            try await repository.insertAsset(mismatchedAsset)
        }

        await expectFailure {
            try await repository.insertReadingProgress(
                ReadingProgress(
                    bookID: firstBook.id,
                    chapterID: chapter.id,
                    stableBlockID: nil,
                    textQuote: nil,
                    contextBefore: nil,
                    contextAfter: nil,
                    fractionInChapter: 1.5,
                    overallProgress: 0.5,
                    lastReadAt: referenceDate
                )
            )
        }
    }

    @Test("Book deletion cascades owned data while linked authors are restricted")
    func cascadeAndRestrictRulesAreEnforced() async throws {
        let repository = try makeRepository()
        let book = makeBook(title: "Owned Records")
        let author = Author(displayName: "Protected Author")
        let tag = Tag(name: "Protected Tag")
        let chapter = Chapter(bookID: book.id, title: "Chapter", position: 0)

        try await repository.insertBook(book)
        try await repository.insertAuthor(author)
        try await repository.linkAuthor(BookAuthor(bookID: book.id, authorID: author.id, position: 0))
        try await repository.insertTag(tag)
        try await repository.linkTag(BookTag(bookID: book.id, tagID: tag.id))
        try await repository.insertChapter(chapter)
        try await repository.insertReadingProgress(
            ReadingProgress(
                bookID: book.id,
                chapterID: chapter.id,
                stableBlockID: nil,
                textQuote: nil,
                contextBefore: nil,
                contextAfter: nil,
                fractionInChapter: 0.5,
                overallProgress: 0.5,
                lastReadAt: referenceDate
            )
        )
        try await repository.insertBookmark(
            Bookmark(bookID: book.id, chapterID: chapter.id, createdAt: referenceDate, updatedAt: referenceDate)
        )

        await expectFailure {
            try await repository.database.write { database in
                _ = try Author.deleteOne(database, key: author.id.databaseString)
            }
        }

        try await repository.moveBookToTrash(id: book.id, at: referenceDate)
        try await repository.deleteBookPermanently(id: book.id)
        let counts = try await entityCounts(repository.database)
        #expect(counts.books == 0)
        #expect(counts.bookAuthors == 0)
        #expect(counts.bookTags == 0)
        #expect(counts.chapters == 0)
        #expect(counts.readingProgress == 0)
        #expect(counts.bookmarks == 0)
        #expect(counts.authors == 1)
        #expect(counts.tags == 1)
    }

    @Test("Failed transactions roll back every write")
    func failedTransactionRollsBack() async throws {
        let repository = try makeRepository()
        let book = makeBook(title: "Rolled Back")

        await expectFailure {
            try await repository.database.write { database in
                try book.insert(database)
                throw PersistenceProbeError.expectedRollback
            }
        }

        #expect(try await repository.fetchBook(id: book.id) == nil)
    }

    @Test("Author and chapter ordering is explicit and transactional")
    func orderingIsExplicitAndTransactional() async throws {
        let repository = try makeRepository()
        let book = makeBook(title: "Ordered Book")
        let authorA = Author(displayName: "Author A")
        let authorB = Author(displayName: "Author B")
        try await repository.insertBook(book)
        try await repository.insertAuthor(authorA)
        try await repository.insertAuthor(authorB)
        try await repository.linkAuthor(BookAuthor(bookID: book.id, authorID: authorA.id, position: 1))
        try await repository.linkAuthor(BookAuthor(bookID: book.id, authorID: authorB.id, position: 0))
        #expect(try await repository.authors(forBookID: book.id).map(\.id) == [authorB.id, authorA.id])

        let first = Chapter(bookID: book.id, title: "First", position: 0)
        let second = Chapter(bookID: book.id, title: "Second", position: 1)
        try await repository.insertChapter(first)
        try await repository.insertChapter(second)
        try await repository.replaceChapterOrder(bookID: book.id, orderedChapterIDs: [second.id, first.id])
        #expect(try await repository.chapters(forBookID: book.id).map(\.id) == [second.id, first.id])

        await expectFailure {
            try await repository.replaceChapterOrder(bookID: book.id, orderedChapterIDs: [first.id])
        }
        #expect(try await repository.chapters(forBookID: book.id).map(\.id) == [second.id, first.id])
    }

    @Test("Observation emits the initial state and committed changes")
    func observationEmitsCommittedChanges() async throws {
        let repository = try makeRepository()
        var iterator = repository.observeLibraryBooks().makeAsyncIterator()

        let initial = try await iterator.next()
        #expect(initial == [])

        let book = makeBook(title: "Observed Book")
        try await repository.insertBook(book)

        let updated = try await iterator.next()
        #expect(updated?.map(\.id) == [book.id])
    }

    @Test("Test database factories never select the production library path")
    func testFactoriesAvoidProductionPath() async throws {
        let memoryDatabase = try LibraryDatabase.makeInMemory()
        #expect(!memoryDatabase.location.isProduction)
        #expect(memoryDatabase.location.databaseURL == nil)

        let directoryURL = temporaryDirectory(named: "path-proof")
        let productionURL = try LibraryDatabase.productionDatabaseURL()
        do {
            let temporaryDatabase = try LibraryDatabase.makeTemporary(in: directoryURL)
            #expect(!temporaryDatabase.location.isProduction)
            #expect(temporaryDatabase.location.databaseURL != productionURL)
            #expect(temporaryDatabase.location.databaseURL?.path.hasPrefix(directoryURL.path) == true)
        }

        try FileManager.default.removeItem(at: directoryURL)
    }

#if DEBUG
    @Test("Debug sample seed is idempotent and reset returns a valid empty library")
    func debugSeedAndReset() async throws {
        let repository = try makeRepository()

        #expect(try await repository.seedSampleLibrary(referenceDate: referenceDate))
        #expect(try await repository.fetchLibraryBooks().count == 8)
        #expect(try await !repository.seedSampleLibrary(referenceDate: referenceDate))

        try await repository.resetSampleLibrary()
        #expect(try await repository.fetchLibraryBooks().isEmpty)
        #expect(try await repository.database.diagnostics().foreignKeysEnabled)
    }
#endif

    private func makeRepository() throws -> GRDBLibraryRepository {
        GRDBLibraryRepository(database: try LibraryDatabase.makeInMemory())
    }

    private func makeBook(title: String, favorite: Bool = false) -> Book {
        Book(
            title: title,
            summary: "Fixture summary",
            isFavorite: favorite,
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
    }

    private func temporaryDirectory(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "iEvelyn-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func entityCounts(_ database: LibraryDatabase) async throws -> EntityCounts {
        try await database.read { database in
            EntityCounts(
                books: try Book.fetchCount(database),
                authors: try Author.fetchCount(database),
                bookAuthors: try BookAuthor.fetchCount(database),
                chapters: try Chapter.fetchCount(database),
                assets: try Asset.fetchCount(database),
                tags: try Tag.fetchCount(database),
                bookTags: try BookTag.fetchCount(database),
                readingProgress: try ReadingProgress.fetchCount(database),
                bookmarks: try Bookmark.fetchCount(database)
            )
        }
    }

    private func expectFailure(
        _ operation: () async throws -> Void,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        do {
            try await operation()
            Issue.record("Expected the operation to fail", sourceLocation: sourceLocation)
        } catch {
            // The specific database error varies by SQLite release; failure is the contract under test.
        }
    }
}

private nonisolated struct EntityCounts: Equatable, Sendable {
    let books: Int
    let authors: Int
    let bookAuthors: Int
    let chapters: Int
    let assets: Int
    let tags: Int
    let bookTags: Int
    let readingProgress: Int
    let bookmarks: Int
}

private nonisolated enum PersistenceProbeError: Error {
    case expectedRollback
}
