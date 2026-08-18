import Foundation
import GRDB

nonisolated protocol LibraryRepository: Sendable {
    func observeLibraryBooks() -> AsyncThrowingStream<[LibraryBook], Error>
    func searchLibrary(
        _ query: String,
        scope: LibrarySearchScope,
        trashScope: LibrarySearchTrashScope
    ) async throws -> [LibrarySearchResult]
    func rebuildSearchIndex() async throws -> LibrarySearchRepairReport
    func createBook(metadata: BookMetadataInput, at date: Date) async throws -> UUID
    func updateBook(id: UUID, metadata: BookMetadataInput, at date: Date) async throws
    func createBook(
        metadata: BookMetadataInput,
        contentChapters: [ImportedBookChapter],
        at date: Date
    ) async throws -> UUID
    func updateBook(
        id: UUID,
        metadata: BookMetadataInput,
        chapterUpdate: BookChapterUpdate,
        at date: Date
    ) async throws
    func setFavorite(bookID: UUID, isFavorite: Bool, at date: Date) async throws
    func moveBookToTrash(id: UUID, at date: Date) async throws
    func moveBooksToTrash(ids: [UUID], at date: Date) async throws
    func restoreBook(id: UUID, at date: Date) async throws
    func markBookOpened(id: UUID, at date: Date) async throws
    func deleteBookPermanently(id: UUID) async throws
    func emptyTrash() async throws -> Int
    func addCovers(bookID: UUID, from sourceURLs: [URL], at date: Date) async throws
    func setCurrentCover(bookID: UUID, coverID: UUID, at date: Date) async throws
    func removeCover(bookID: UUID, coverID: UUID, at date: Date) async throws
    func coverAssets(forBookID bookID: UUID) async throws -> [Asset]
    func coverThumbnailData(for asset: Asset) async throws -> Data
    func assets(forBookID bookID: UUID) async throws -> [Asset]
    func bookAssetPayload(for url: URL) async throws -> LibraryAssetPayload
    func observeChapters(forBookID bookID: UUID) -> AsyncThrowingStream<[Chapter], Error>
    func chapters(forBookID bookID: UUID) async throws -> [Chapter]
    func readingProgress(forBookID bookID: UUID) async throws -> ReadingProgress?
    func saveReadingProgress(_ progress: ReadingProgress) async throws
    func clearReadingProgress(bookIDs: [UUID]) async throws
    func observeBookmarks(forBookID bookID: UUID) -> AsyncThrowingStream<[Bookmark], Error>
    func createBookmark(_ bookmark: Bookmark) async throws
    func deleteBookmark(id: UUID, bookID: UUID) async throws
    func createChapter(bookID: UUID, title: String, at date: Date) async throws -> UUID
    func renameChapter(id: UUID, title: String, at date: Date) async throws
    func updateChapterMarkdown(
        id: UUID,
        markdown: String,
        expectedRenderRevision: Int,
        at date: Date
    ) async throws -> Chapter
    func duplicateChapter(id: UUID, at date: Date) async throws -> UUID
    func deleteChapter(id: UUID, at date: Date) async throws -> ChapterDeletion
    func restoreChapterDeletion(_ deletion: ChapterDeletion, at date: Date) async throws
    func reorderChapters(bookID: UUID, orderedChapterIDs: [UUID], at date: Date) async throws
}

nonisolated enum LibraryRepositoryError: LocalizedError, Equatable {
    case chapterOrderDoesNotMatchBook
    case chapterNotFound
    case chapterAlreadyExists
    case chapterPositionLimitReached
    case chapterRevisionLimitReached
    case bookContentRequired
    case bookmarkNotFound
    case bookNotFound
    case bookIsInTrash
    case coverNotFound
    case permanentDeleteRequiresTrash
    case readOnlyRepository

    var errorDescription: String? {
        switch self {
        case .chapterOrderDoesNotMatchBook:
            "The chapter order must contain every chapter in the book exactly once."
        case .chapterNotFound:
            "The selected chapter no longer exists."
        case .chapterAlreadyExists:
            "The deleted chapter has already been restored."
        case .chapterPositionLimitReached:
            "The chapter order could not be changed because its stored positions are out of range."
        case .chapterRevisionLimitReached:
            "The chapter could not be saved because its revision limit was reached."
        case .bookContentRequired:
            "A book must contain at least one imported chapter."
        case .bookmarkNotFound:
            "The selected bookmark no longer exists."
        case .bookNotFound:
            "The selected book no longer exists."
        case .bookIsInTrash:
            "Restore the book before changing its chapters."
        case .coverNotFound:
            "The selected cover no longer exists for this book."
        case .permanentDeleteRequiresTrash:
            "Move the book to Trash before deleting it permanently."
        case .readOnlyRepository:
            "This library is read-only."
        }
    }
}

nonisolated struct ChapterRevisionConflict: LocalizedError, Equatable, Sendable {
    let storedChapter: Chapter

    var errorDescription: String? {
        "This chapter changed in another window. Reload that version or explicitly overwrite it with this draft."
    }
}

extension LibraryRepository {
    func searchLibrary(
        _ query: String,
        scope: LibrarySearchScope,
        trashScope: LibrarySearchTrashScope
    ) async throws -> [LibrarySearchResult] {
        []
    }

    func rebuildSearchIndex() async throws -> LibrarySearchRepairReport {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func createBook(metadata: BookMetadataInput, at date: Date) async throws -> UUID {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func updateBook(id: UUID, metadata: BookMetadataInput, at date: Date) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func createBook(
        metadata: BookMetadataInput,
        contentChapters: [ImportedBookChapter],
        at date: Date
    ) async throws -> UUID {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func updateBook(
        id: UUID,
        metadata: BookMetadataInput,
        chapterUpdate: BookChapterUpdate,
        at date: Date
    ) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func setFavorite(bookID: UUID, isFavorite: Bool, at date: Date) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func moveBookToTrash(id: UUID, at date: Date) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func moveBooksToTrash(ids: [UUID], at date: Date) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func restoreBook(id: UUID, at date: Date) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func markBookOpened(id: UUID, at date: Date) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func deleteBookPermanently(id: UUID) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func emptyTrash() async throws -> Int {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func addCovers(bookID: UUID, from sourceURLs: [URL], at date: Date) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func setCurrentCover(bookID: UUID, coverID: UUID, at date: Date) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func removeCover(bookID: UUID, coverID: UUID, at date: Date) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func coverAssets(forBookID bookID: UUID) async throws -> [Asset] { [] }

    func coverThumbnailData(for asset: Asset) async throws -> Data {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func assets(forBookID bookID: UUID) async throws -> [Asset] {
        []
    }

    func bookAssetPayload(for url: URL) async throws -> LibraryAssetPayload {
        throw LibraryRepositoryError.readOnlyRepository
    }

    nonisolated func observeChapters(forBookID bookID: UUID) -> AsyncThrowingStream<[Chapter], Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: LibraryRepositoryError.readOnlyRepository)
        }
    }

    func chapters(forBookID bookID: UUID) async throws -> [Chapter] {
        []
    }

    func readingProgress(forBookID bookID: UUID) async throws -> ReadingProgress? {
        nil
    }

    func saveReadingProgress(_ progress: ReadingProgress) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func clearReadingProgress(bookIDs: [UUID]) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    nonisolated func observeBookmarks(forBookID bookID: UUID) -> AsyncThrowingStream<[Bookmark], Error> {
        AsyncThrowingStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }

    func createBookmark(_ bookmark: Bookmark) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func deleteBookmark(id: UUID, bookID: UUID) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func createChapter(bookID: UUID, title: String, at date: Date) async throws -> UUID {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func renameChapter(id: UUID, title: String, at date: Date) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func updateChapterMarkdown(
        id: UUID,
        markdown: String,
        expectedRenderRevision: Int,
        at date: Date
    ) async throws -> Chapter {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func duplicateChapter(id: UUID, at date: Date) async throws -> UUID {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func deleteChapter(id: UUID, at date: Date) async throws -> ChapterDeletion {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func restoreChapterDeletion(_ deletion: ChapterDeletion, at date: Date) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func reorderChapters(bookID: UUID, orderedChapterIDs: [UUID], at date: Date) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }
}

nonisolated final class GRDBLibraryRepository: LibraryRepository, Sendable {
    let database: LibraryDatabase
    let assetStore: LibraryAssetStore

    init(database: LibraryDatabase, assetStore: LibraryAssetStore? = nil) {
        self.database = database
        self.assetStore = assetStore ?? LibraryAssetStore.defaultStore(for: database)
    }

    func observeLibraryBooks() -> AsyncThrowingStream<[LibraryBook], Error> {
        let observation = ValueObservation.tracking(
            regions: [
                Book.all(),
                Author.all(),
                BookAuthor.all(),
                Tag.all(),
                BookTag.all(),
                ReadingProgress.all(),
                Asset.all()
            ],
            fetch: Self.fetchLibraryBooks
        )
        let values = observation.values(
            in: database.writer,
            bufferingPolicy: .bufferingNewest(1)
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await books in values {
                        continuation.yield(books)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func searchLibrary(
        _ query: String,
        scope: LibrarySearchScope,
        trashScope: LibrarySearchTrashScope
    ) async throws -> [LibrarySearchResult] {
        let expression = try LibrarySearchQueryBuilder.matchExpression(
            for: query,
            scope: scope
        )
        try Task.checkCancellation()
        let rows = try await database.read { database in
            try LibrarySearchRow.fetchAll(
                database,
                sql: """
                    SELECT
                        documents.documentKey,
                        documents.bookID,
                        books.title AS bookTitle,
                        COALESCE((
                            SELECT group_concat(displayName, ', ')
                            FROM (
                                SELECT authors.displayName
                                FROM authors
                                JOIN bookAuthors ON bookAuthors.authorID = authors.id
                                WHERE bookAuthors.bookID = books.id
                                ORDER BY bookAuthors.position, authors.normalizedName, authors.id
                            )
                        ), '') AS authorLine,
                        documents.chapterID,
                        chapters.title AS storedChapterTitle,
                        documents.stableBlockID,
                        documents.fractionInChapter,
                        documents.kind,
                        documents.body,
                        highlight(librarySearchIndex, 0, '\(LibrarySearchIndexer.highlightStart)', '\(LibrarySearchIndexer.highlightEnd)') AS highlightedTitle,
                        highlight(librarySearchIndex, 1, '\(LibrarySearchIndexer.highlightStart)', '\(LibrarySearchIndexer.highlightEnd)') AS highlightedSubtitle,
                        highlight(librarySearchIndex, 2, '\(LibrarySearchIndexer.highlightStart)', '\(LibrarySearchIndexer.highlightEnd)') AS highlightedAuthors,
                        highlight(librarySearchIndex, 3, '\(LibrarySearchIndexer.highlightStart)', '\(LibrarySearchIndexer.highlightEnd)') AS highlightedTags,
                        highlight(librarySearchIndex, 4, '\(LibrarySearchIndexer.highlightStart)', '\(LibrarySearchIndexer.highlightEnd)') AS highlightedChapterTitle,
                        snippet(librarySearchIndex, 5, '\(LibrarySearchIndexer.highlightStart)', '\(LibrarySearchIndexer.highlightEnd)', '…', 32) AS bodySnippet
                    FROM librarySearchIndex
                    JOIN librarySearchDocuments AS documents
                        ON documents.id = librarySearchIndex.rowid
                    JOIN books ON books.id = documents.bookID
                    LEFT JOIN chapters ON chapters.id = documents.chapterID
                    WHERE librarySearchIndex MATCH ?
                      AND ((? = 'activeLibrary' AND books.trashedAt IS NULL)
                           OR (? = 'trash' AND books.trashedAt IS NOT NULL))
                    ORDER BY
                        bm25(librarySearchIndex, 12.0, 8.0, 7.0, 6.0, 5.0, 1.0),
                        books.title COLLATE NOCASE,
                        COALESCE(chapters.position, -1),
                        documents.ordinal,
                        documents.id
                    LIMIT 250
                    """,
                arguments: [expression, trashScope.rawValue, trashScope.rawValue]
            )
        }
        try Task.checkCancellation()
        return rows.map(\.searchResult)
    }

    func rebuildSearchIndex() async throws -> LibrarySearchRepairReport {
        try await database.write { database in
            try LibrarySearchIndexer.rebuildAll(database)
        }
    }

    func observeChapters(forBookID bookID: UUID) -> AsyncThrowingStream<[Chapter], Error> {
        let observation = ValueObservation.tracking { database in
            try Self.fetchChapters(forBookID: bookID, database: database)
        }
        let values = observation.values(
            in: database.writer,
            bufferingPolicy: .bufferingNewest(1)
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chapters in values {
                        continuation.yield(chapters)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func observeBookmarks(forBookID bookID: UUID) -> AsyncThrowingStream<[Bookmark], Error> {
        let observation = ValueObservation.tracking { database in
            try Bookmark.fetchAll(
                database,
                sql: """
                    SELECT * FROM bookmarks
                    WHERE bookID = ?
                    ORDER BY createdAt, id
                    """,
                arguments: [bookID.databaseString]
            )
        }
        let values = observation.values(
            in: database.writer,
            bufferingPolicy: .bufferingNewest(1)
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await bookmarks in values {
                        continuation.yield(bookmarks)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func readingProgress(forBookID bookID: UUID) async throws -> ReadingProgress? {
        try await database.read { database in
            try ReadingProgress.fetchOne(database, key: bookID.databaseString)
        }
    }

    func saveReadingProgress(_ progress: ReadingProgress) async throws {
        try await database.write { database in
            guard var book = try Book.fetchOne(database, key: progress.bookID.databaseString) else {
                throw LibraryRepositoryError.bookNotFound
            }
            guard book.trashedAt == nil else {
                throw LibraryRepositoryError.bookIsInTrash
            }
            if let stored = try ReadingProgress.fetchOne(
                database,
                key: progress.bookID.databaseString
            ), stored.lastReadAt > progress.lastReadAt {
                return
            }

            try progress.save(database)
            if book.lastOpenedAt.map({ $0 < progress.lastReadAt }) ?? true {
                book.lastOpenedAt = progress.lastReadAt
                try book.update(database)
            }
        }
    }

    func clearReadingProgress(bookIDs: [UUID]) async throws {
        let bookIDs = Self.uniqueBookIDs(bookIDs)
        guard !bookIDs.isEmpty else { return }

        try await database.write { database in
            for bookID in bookIDs {
                guard let book = try Book.fetchOne(database, key: bookID.databaseString) else {
                    throw LibraryRepositoryError.bookNotFound
                }
                guard book.trashedAt == nil else {
                    throw LibraryRepositoryError.bookIsInTrash
                }
            }

            for bookID in bookIDs {
                _ = try ReadingProgress.deleteOne(database, key: bookID.databaseString)
            }
            // The library projection spans several independently fetched tables.
            // Explicitly invalidate its progress region after primary-key deletes.
            try database.notifyChanges(in: ReadingProgress.all())
        }
    }

    func createBookmark(_ bookmark: Bookmark) async throws {
        try await database.write { database in
            _ = try Self.fetchEditableBook(id: bookmark.bookID, database: database)
            var bookmark = bookmark
            bookmark.label = nil
            bookmark.note = nil
            try bookmark.insert(database)
        }
    }

    func deleteBookmark(id: UUID, bookID: UUID) async throws {
        try await database.write { database in
            guard let bookmark = try Bookmark.fetchOne(database, key: id.databaseString),
                  bookmark.bookID == bookID else {
                throw LibraryRepositoryError.bookmarkNotFound
            }
            _ = try Self.fetchEditableBook(id: bookID, database: database)
            _ = try bookmark.delete(database)
        }
    }

    func fetchLibraryBooks() async throws -> [LibraryBook] {
        try await database.read(Self.fetchLibraryBooks)
    }

    func createBook(metadata: BookMetadataInput, at date: Date = .now) async throws -> UUID {
        let metadata = try metadata.validated()
        let book = Book(
            title: metadata.title,
            subtitle: metadata.subtitle,
            summary: metadata.summary,
            createdAt: date,
            updatedAt: date,
            lastOpenedAt: nil
        )

        try await database.write { database in
            try book.insert(database)
            try Self.replaceAuthors(
                forBookID: book.id,
                displayNames: metadata.authors,
                at: date,
                database: database
            )
            try Self.replaceTags(
                forBookID: book.id,
                names: metadata.tags,
                at: date,
                database: database
            )
            try LibrarySearchIndexer.reindexBook(bookID: book.id, database: database)
        }
        return book.id
    }

    func updateBook(
        id: UUID,
        metadata: BookMetadataInput,
        at date: Date = .now
    ) async throws {
        let metadata = try metadata.validated()

        try await database.write { database in
            guard var book = try Book.fetchOne(database, key: id.databaseString) else {
                throw LibraryRepositoryError.bookNotFound
            }

            book.title = metadata.title
            book.subtitle = metadata.subtitle
            book.summary = metadata.summary
            book.updatedAt = date
            try book.update(database)

            try Self.replaceAuthors(
                forBookID: id,
                displayNames: metadata.authors,
                at: date,
                database: database
            )
            try Self.replaceTags(
                forBookID: id,
                names: metadata.tags,
                at: date,
                database: database
            )
            try LibrarySearchIndexer.reindexBook(bookID: id, database: database)
        }
    }

    func createBook(
        metadata: BookMetadataInput,
        contentChapters: [ImportedBookChapter],
        at date: Date = .now
    ) async throws -> UUID {
        let metadata = try metadata.validated()
        let contentChapters = try Self.validatedImportedChapters(contentChapters)
        guard !contentChapters.isEmpty else {
            throw LibraryRepositoryError.bookContentRequired
        }

        let book = Book(
            title: metadata.title,
            subtitle: metadata.subtitle,
            summary: metadata.summary,
            createdAt: date,
            updatedAt: date,
            lastOpenedAt: nil
        )
        try await database.write { database in
            try book.insert(database)
            try Self.replaceAuthors(
                forBookID: book.id,
                displayNames: metadata.authors,
                at: date,
                database: database
            )
            try Self.replaceTags(
                forBookID: book.id,
                names: metadata.tags,
                at: date,
                database: database
            )
            for (position, importedChapter) in contentChapters.enumerated() {
                try Chapter(
                    bookID: book.id,
                    title: importedChapter.title,
                    markdown: importedChapter.markdown,
                    position: position,
                    createdAt: date,
                    updatedAt: date
                )
                .insert(database)
            }
            try LibrarySearchIndexer.reindexBook(bookID: book.id, database: database)
        }
        return book.id
    }

    func updateBook(
        id: UUID,
        metadata: BookMetadataInput,
        chapterUpdate: BookChapterUpdate,
        at date: Date = .now
    ) async throws {
        let metadata = try metadata.validated()
        let validatedChapterUpdate: BookChapterUpdate
        switch chapterUpdate {
        case .unchanged:
            validatedChapterUpdate = .unchanged
        case .replace(let chapters):
            let chapters = try Self.validatedImportedChapters(chapters)
            guard !chapters.isEmpty else { throw LibraryRepositoryError.bookContentRequired }
            validatedChapterUpdate = .replace(chapters)
        case .append(let chapters):
            let chapters = try Self.validatedImportedChapters(chapters)
            guard !chapters.isEmpty else { throw LibraryRepositoryError.bookContentRequired }
            validatedChapterUpdate = .append(chapters)
        }

        try await database.write { database in
            var book = try Self.fetchEditableBook(id: id, database: database)

            book.title = metadata.title
            book.subtitle = metadata.subtitle
            book.summary = metadata.summary
            book.updatedAt = date
            try book.update(database)
            try Self.replaceAuthors(
                forBookID: id,
                displayNames: metadata.authors,
                at: date,
                database: database
            )
            try Self.replaceTags(
                forBookID: id,
                names: metadata.tags,
                at: date,
                database: database
            )

            switch validatedChapterUpdate {
            case .unchanged:
                break
            case .replace(let chapters):
                try Self.replaceImportedChapters(
                    chapters,
                    forBookID: id,
                    at: date,
                    database: database
                )
            case .append(let chapters):
                try Self.appendImportedChapters(
                    chapters,
                    toBookID: id,
                    at: date,
                    database: database
                )
            }

            try LibrarySearchIndexer.reindexBook(bookID: id, database: database)
        }
    }

    func setFavorite(
        bookID: UUID,
        isFavorite: Bool,
        at date: Date = .now
    ) async throws {
        try await database.write { database in
            guard var book = try Book.fetchOne(database, key: bookID.databaseString) else {
                throw LibraryRepositoryError.bookNotFound
            }
            guard book.isFavorite != isFavorite else { return }
            book.isFavorite = isFavorite
            book.updatedAt = date
            try book.update(database)
        }
    }

    func moveBookToTrash(id: UUID, at date: Date = .now) async throws {
        try await database.write { database in
            guard var book = try Book.fetchOne(database, key: id.databaseString) else {
                throw LibraryRepositoryError.bookNotFound
            }
            guard book.trashedAt == nil else { return }
            book.trashedAt = date
            book.updatedAt = date
            try book.update(database)
        }
    }

    func moveBooksToTrash(ids: [UUID], at date: Date = .now) async throws {
        let bookIDs = Self.uniqueBookIDs(ids)
        guard !bookIDs.isEmpty else { return }

        try await database.write { database in
            var books: [Book] = []
            books.reserveCapacity(bookIDs.count)
            for bookID in bookIDs {
                guard let book = try Book.fetchOne(database, key: bookID.databaseString) else {
                    throw LibraryRepositoryError.bookNotFound
                }
                books.append(book)
            }

            for var book in books where book.trashedAt == nil {
                book.trashedAt = date
                book.updatedAt = date
                try book.update(database)
            }
        }
    }

    func restoreBook(id: UUID, at date: Date = .now) async throws {
        try await database.write { database in
            guard var book = try Book.fetchOne(database, key: id.databaseString) else {
                throw LibraryRepositoryError.bookNotFound
            }
            guard book.trashedAt != nil else { return }
            book.trashedAt = nil
            book.updatedAt = date
            try book.update(database)
        }
    }

    func markBookOpened(id: UUID, at date: Date = .now) async throws {
        try await database.write { database in
            guard var book = try Book.fetchOne(database, key: id.databaseString) else {
                throw LibraryRepositoryError.bookNotFound
            }
            guard book.trashedAt == nil, book.lastOpenedAt != date else { return }
            book.lastOpenedAt = date
            try book.update(database)
        }
    }

    func insertBook(_ book: Book) async throws {
        try await database.write { database in
            try book.insert(database)
            try LibrarySearchIndexer.reindexBook(bookID: book.id, database: database)
        }
    }

    func updateBook(_ book: Book) async throws {
        try await database.write { database in
            try book.update(database)
            try LibrarySearchIndexer.reindexBook(bookID: book.id, database: database)
        }
    }

    func fetchBook(id: UUID) async throws -> Book? {
        try await database.read { database in
            try Book.fetchOne(database, key: id.databaseString)
        }
    }

    func deleteBookPermanently(id: UUID) async throws {
        try await database.write { database in
            guard let book = try Book.fetchOne(database, key: id.databaseString) else {
                throw LibraryRepositoryError.bookNotFound
            }
            guard book.trashedAt != nil else {
                throw LibraryRepositoryError.permanentDeleteRequiresTrash
            }
            _ = try book.delete(database)
        }

        let report = await assetStore.removeBookStorage(bookID: id)
        if report.failedRemovalCount > 0 {
            throw LibraryAssetError.cleanupIncomplete(
                completedAction: "The book was permanently deleted",
                remainingFileCount: report.failedRemovalCount
            )
        }
    }

    func emptyTrash() async throws -> Int {
        let bookIDs = try await database.write { database in
            let books = try Book.fetchAll(
                database,
                sql: "SELECT * FROM books WHERE trashedAt IS NOT NULL ORDER BY id"
            )
            for book in books {
                _ = try book.delete(database)
            }
            return books.map(\.id)
        }

        try await removeOwnedStorage(
            bookIDs: bookIDs,
            completedAction: "Trash was emptied"
        )
        return bookIDs.count
    }

    func addCovers(
        bookID: UUID,
        from sourceURLs: [URL],
        at date: Date = .now
    ) async throws {
        guard !sourceURLs.isEmpty else { return }
        var preparedAssets: [PreparedLibraryAsset] = []
        do {
            for sourceURL in sourceURLs {
                preparedAssets.append(
                    try await assetStore.prepareCoverImport(
                        bookID: bookID,
                        sourceURL: sourceURL,
                        at: date
                    )
                )
            }
            let preparedAssetsForInsertion = preparedAssets

            try await database.write { database in
                var book = try Self.fetchEditableBook(id: bookID, database: database)
                let hasCurrentCover = try Self.fetchCurrentCover(
                    bookID: bookID,
                    database: database
                ) != nil
                for (index, preparedAsset) in preparedAssetsForInsertion.enumerated() {
                    var asset = preparedAsset.asset
                    asset.isCurrentCover = !hasCurrentCover
                        && index == preparedAssetsForInsertion.startIndex
                    try asset.insert(database)
                }
                book.updatedAt = date
                try book.update(database)
            }
        } catch {
            for preparedAsset in preparedAssets {
                _ = await assetStore.discardPreparedAsset(preparedAsset)
            }
            throw error
        }
    }

    func setCurrentCover(
        bookID: UUID,
        coverID: UUID,
        at date: Date = .now
    ) async throws {
        try await database.write { database in
            var book = try Self.fetchEditableBook(id: bookID, database: database)
            guard var selectedCover = try Self.fetchCover(
                bookID: bookID,
                coverID: coverID,
                database: database
            ) else {
                throw LibraryRepositoryError.coverNotFound
            }

            try database.execute(
                sql: """
                    UPDATE assets SET isCurrentCover = 0
                    WHERE bookID = ? AND purpose = ? AND isCurrentCover = 1
                    """,
                arguments: [bookID.databaseString, AssetPurpose.cover.rawValue]
            )
            selectedCover.isCurrentCover = true
            selectedCover.updatedAt = date
            try selectedCover.update(database)
            book.updatedAt = date
            try book.update(database)
        }
    }

    func removeCover(
        bookID: UUID,
        coverID: UUID,
        at date: Date = .now
    ) async throws {
        let removedCover = try await database.write { database in
            var book = try Self.fetchEditableBook(id: bookID, database: database)
            guard let cover = try Self.fetchCover(
                bookID: bookID,
                coverID: coverID,
                database: database
            ) else {
                throw LibraryRepositoryError.coverNotFound
            }

            _ = try cover.delete(database)
            if cover.isCurrentCover,
               var promotedCover = try Self.fetchFirstCover(
                   bookID: bookID,
                   database: database
               ) {
                promotedCover.isCurrentCover = true
                promotedCover.updatedAt = date
                try promotedCover.update(database)
            }
            book.updatedAt = date
            try book.update(database)
            return cover
        }

        let report = await assetStore.removeFiles(for: [removedCover])
        if report.failedRemovalCount > 0 {
            throw LibraryAssetError.cleanupIncomplete(
                completedAction: "The cover was removed",
                remainingFileCount: report.failedRemovalCount
            )
        }
    }

    func coverAssets(forBookID bookID: UUID) async throws -> [Asset] {
        try await database.read { database in
            try Asset.fetchAll(
                database,
                sql: """
                    SELECT * FROM assets
                    WHERE bookID = ? AND purpose = ?
                    ORDER BY isCurrentCover DESC, createdAt, id
                    """,
                arguments: [bookID.databaseString, AssetPurpose.cover.rawValue]
            )
        }
    }

    func coverThumbnailData(for asset: Asset) async throws -> Data {
        try await assetStore.thumbnailData(for: asset)
    }

    func assets(forBookID bookID: UUID) async throws -> [Asset] {
        try await database.read { database in
            try Asset
                .filter(Column("bookID") == bookID.databaseString)
                .order(Column("id"))
                .fetchAll(database)
        }
    }

    func bookAssetPayload(for url: URL) async throws -> LibraryAssetPayload {
        let reference = try BookAssetReference(url: url)
        guard let asset = try await database.read({ database in
            try Asset.fetchOne(
                database,
                sql: "SELECT * FROM assets WHERE id = ? AND bookID = ?",
                arguments: [reference.assetID.databaseString, reference.bookID.databaseString]
            )
        }) else {
            throw LibraryAssetError.assetReferenceNotFound
        }
        let data = try await assetStore.storedData(for: asset)
        return LibraryAssetPayload(data: data, mediaType: asset.mediaType)
    }

    func bookAssetURL(for asset: Asset) throws -> URL {
        try BookAssetReference(bookID: asset.bookID, assetID: asset.id).url()
    }

    func resolveBookAssetURL(_ url: URL) async throws -> URL {
        let reference = try BookAssetReference(url: url)
        guard let asset = try await database.read({ database in
            try Asset.fetchOne(
                database,
                sql: "SELECT * FROM assets WHERE id = ? AND bookID = ?",
                arguments: [reference.assetID.databaseString, reference.bookID.databaseString]
            )
        }) else {
            throw LibraryAssetError.assetReferenceNotFound
        }
        return try await assetStore.storedFileURL(for: asset)
    }

    func auditAssetStorage() async throws -> AssetStorageAudit {
        let assets = try await fetchAssets()
        return await assetStore.audit(referencedAssets: assets)
    }

    func prepareAssetStorage() async throws {
        try await assetStore.prepareLibraryLayout()
    }

    func repairAssetStorage() async throws -> AssetStorageRepairReport {
        let assets = try await fetchAssets()
        return await assetStore.repair(referencedAssets: assets)
    }

    func fetchAssets() async throws -> [Asset] {
        try await database.read { database in
            try Asset.fetchAll(database)
        }
    }

    func insertAuthor(_ author: Author) async throws {
        try await database.write { database in
            try author.insert(database)
        }
    }

    func linkAuthor(_ link: BookAuthor) async throws {
        try await database.write { database in
            try link.insert(database)
            try LibrarySearchIndexer.reindexBook(bookID: link.bookID, database: database)
        }
    }

    func authors(forBookID bookID: UUID) async throws -> [Author] {
        try await database.read { database in
            try Author.fetchAll(
                database,
                sql: """
                    SELECT authors.*
                    FROM authors
                    JOIN bookAuthors ON bookAuthors.authorID = authors.id
                    WHERE bookAuthors.bookID = ?
                    ORDER BY bookAuthors.position, authors.normalizedName, authors.id
                    """,
                arguments: [bookID.databaseString]
            )
        }
    }

    func insertChapter(_ chapter: Chapter) async throws {
        try await database.write { database in
            try chapter.insert(database)
            try LibrarySearchIndexer.reindexBook(bookID: chapter.bookID, database: database)
        }
    }

    func chapters(forBookID bookID: UUID) async throws -> [Chapter] {
        try await database.read { database in
            try Self.fetchChapters(forBookID: bookID, database: database)
        }
    }

    func createChapter(
        bookID: UUID,
        title: String,
        at date: Date = .now
    ) async throws -> UUID {
        let title = try ChapterTitleInput(title: title).validated()
        let chapter = try await database.write { database in
            var book = try Self.fetchEditableBook(id: bookID, database: database)
            let position = try Self.nextTemporaryChapterPosition(
                bookID: bookID,
                additionalPositionCount: 1,
                database: database
            )
            let chapter = Chapter(
                bookID: bookID,
                title: title,
                position: position,
                createdAt: date,
                updatedAt: date
            )
            try chapter.insert(database)

            book.updatedAt = date
            try book.update(database)
            try LibrarySearchIndexer.reindexBook(bookID: bookID, database: database)
            return chapter
        }
        return chapter.id
    }

    func renameChapter(
        id: UUID,
        title: String,
        at date: Date = .now
    ) async throws {
        let title = try ChapterTitleInput(title: title).validated()
        try await database.write { database in
            guard var chapter = try Chapter.fetchOne(database, key: id.databaseString) else {
                throw LibraryRepositoryError.chapterNotFound
            }
            var book = try Self.fetchEditableBook(id: chapter.bookID, database: database)
            guard chapter.title != title else { return }

            chapter.title = title
            chapter.updatedAt = date
            try chapter.update(database)

            book.updatedAt = date
            try book.update(database)
            try LibrarySearchIndexer.reindexBook(bookID: chapter.bookID, database: database)
        }
    }

    func updateChapterMarkdown(
        id: UUID,
        markdown: String,
        expectedRenderRevision: Int,
        at date: Date = .now
    ) async throws -> Chapter {
        try await database.write { database in
            guard var chapter = try Chapter.fetchOne(database, key: id.databaseString) else {
                throw LibraryRepositoryError.chapterNotFound
            }
            var book = try Self.fetchEditableBook(id: chapter.bookID, database: database)

            if chapter.markdown == markdown {
                return chapter
            }
            guard chapter.renderRevision == expectedRenderRevision else {
                throw ChapterRevisionConflict(storedChapter: chapter)
            }
            let (nextRevision, overflowed) = chapter.renderRevision.addingReportingOverflow(1)
            guard !overflowed else {
                throw LibraryRepositoryError.chapterRevisionLimitReached
            }

            chapter.markdown = markdown
            chapter.renderRevision = nextRevision
            chapter.sourceHash = nil
            chapter.updatedAt = date
            try chapter.update(database)

            book.updatedAt = date
            try book.update(database)
            try LibrarySearchIndexer.reindexBook(bookID: chapter.bookID, database: database)
            return chapter
        }
    }

    func duplicateChapter(id: UUID, at date: Date = .now) async throws -> UUID {
        try await database.write { database in
            guard let source = try Chapter.fetchOne(database, key: id.databaseString) else {
                throw LibraryRepositoryError.chapterNotFound
            }
            var book = try Self.fetchEditableBook(id: source.bookID, database: database)
            let chapters = try Self.fetchChapters(forBookID: source.bookID, database: database)
            guard let sourceIndex = chapters.firstIndex(where: { $0.id == source.id }) else {
                throw LibraryRepositoryError.chapterNotFound
            }

            let temporaryPosition = try Self.nextTemporaryChapterPosition(
                bookID: source.bookID,
                additionalPositionCount: chapters.count + 2,
                database: database
            )
            let duplicate = Chapter(
                bookID: source.bookID,
                title: source.title,
                markdown: source.markdown,
                position: temporaryPosition,
                renderRevision: source.renderRevision,
                sourceHash: source.sourceHash,
                createdAt: date,
                updatedAt: date
            )
            try duplicate.insert(database)

            var orderedIDs = chapters.map(\.id)
            orderedIDs.insert(duplicate.id, at: sourceIndex + 1)
            try Self.setChapterOrder(
                bookID: source.bookID,
                orderedChapterIDs: orderedIDs,
                updatedAt: date,
                database: database
            )

            book.updatedAt = date
            try book.update(database)
            try LibrarySearchIndexer.reindexBook(bookID: source.bookID, database: database)
            return duplicate.id
        }
    }

    func deleteChapter(id: UUID, at date: Date = .now) async throws -> ChapterDeletion {
        try await database.write { database in
            guard let chapter = try Chapter.fetchOne(database, key: id.databaseString) else {
                throw LibraryRepositoryError.chapterNotFound
            }
            var book = try Self.fetchEditableBook(id: chapter.bookID, database: database)
            let linkedAssetIDs = try UUID.fetchAll(
                database,
                sql: "SELECT id FROM assets WHERE chapterID = ? ORDER BY id",
                arguments: [id.databaseString]
            )
            let hadLinkedReadingProgress = try Bool.fetchOne(
                database,
                sql: "SELECT EXISTS(SELECT 1 FROM readingProgress WHERE chapterID = ?)",
                arguments: [id.databaseString]
            ) ?? false
            let linkedBookmarkIDs = try UUID.fetchAll(
                database,
                sql: "SELECT id FROM bookmarks WHERE chapterID = ? ORDER BY id",
                arguments: [id.databaseString]
            )

            _ = try chapter.delete(database)
            let remainingIDs = try Self.fetchChapters(
                forBookID: chapter.bookID,
                database: database
            )
            .map(\.id)
            try Self.setChapterOrder(
                bookID: chapter.bookID,
                orderedChapterIDs: remainingIDs,
                updatedAt: date,
                database: database
            )

            book.updatedAt = date
            try book.update(database)
            try LibrarySearchIndexer.reindexBook(bookID: chapter.bookID, database: database)
            return ChapterDeletion(
                chapter: chapter,
                linkedAssetIDs: linkedAssetIDs,
                hadLinkedReadingProgress: hadLinkedReadingProgress,
                linkedBookmarkIDs: linkedBookmarkIDs
            )
        }
    }

    func restoreChapterDeletion(
        _ deletion: ChapterDeletion,
        at date: Date = .now
    ) async throws {
        try await database.write { database in
            let deletedChapter = deletion.chapter
            var book = try Self.fetchEditableBook(id: deletedChapter.bookID, database: database)
            guard try Chapter.fetchOne(database, key: deletedChapter.id.databaseString) == nil else {
                throw LibraryRepositoryError.chapterAlreadyExists
            }

            let currentChapters = try Self.fetchChapters(
                forBookID: deletedChapter.bookID,
                database: database
            )
            let temporaryPosition = try Self.nextTemporaryChapterPosition(
                bookID: deletedChapter.bookID,
                additionalPositionCount: currentChapters.count + 2,
                database: database
            )
            var restoredChapter = deletedChapter
            restoredChapter.position = temporaryPosition
            try restoredChapter.insert(database)

            var orderedIDs = currentChapters.map(\.id)
            orderedIDs.insert(
                restoredChapter.id,
                at: min(deletedChapter.position, orderedIDs.count)
            )
            try Self.setChapterOrder(
                bookID: deletedChapter.bookID,
                orderedChapterIDs: orderedIDs,
                updatedAt: date,
                database: database
            )

            if !deletion.linkedAssetIDs.isEmpty {
                try database.execute(
                    sql: """
                        UPDATE assets SET chapterID = ?
                        WHERE bookID = ? AND chapterID IS NULL AND id IN (\(deletion.linkedAssetIDs.map { _ in "?" }.joined(separator: ", ")))
                        """,
                    arguments: StatementArguments(
                        [restoredChapter.id.databaseString, restoredChapter.bookID.databaseString]
                            + deletion.linkedAssetIDs.map(\.databaseString)
                    )
                )
            }
            if deletion.hadLinkedReadingProgress {
                try database.execute(
                    sql: "UPDATE readingProgress SET chapterID = ? WHERE bookID = ? AND chapterID IS NULL",
                    arguments: [restoredChapter.id.databaseString, restoredChapter.bookID.databaseString]
                )
            }
            if !deletion.linkedBookmarkIDs.isEmpty {
                try database.execute(
                    sql: """
                        UPDATE bookmarks SET chapterID = ?
                        WHERE bookID = ? AND chapterID IS NULL AND id IN (\(deletion.linkedBookmarkIDs.map { _ in "?" }.joined(separator: ", ")))
                        """,
                    arguments: StatementArguments(
                        [restoredChapter.id.databaseString, restoredChapter.bookID.databaseString]
                            + deletion.linkedBookmarkIDs.map(\.databaseString)
                    )
                )
            }

            book.updatedAt = date
            try book.update(database)
            try LibrarySearchIndexer.reindexBook(
                bookID: restoredChapter.bookID,
                database: database
            )
        }
    }

    func reorderChapters(
        bookID: UUID,
        orderedChapterIDs: [UUID],
        at date: Date = .now
    ) async throws {
        try await database.write { database in
            var book = try Self.fetchEditableBook(id: bookID, database: database)
            let storedIDs = try Self.fetchChapters(forBookID: bookID, database: database).map(\.id)
            guard storedIDs.count == orderedChapterIDs.count,
                  Set(storedIDs) == Set(orderedChapterIDs) else {
                throw LibraryRepositoryError.chapterOrderDoesNotMatchBook
            }
            guard storedIDs != orderedChapterIDs else { return }

            try Self.setChapterOrder(
                bookID: bookID,
                orderedChapterIDs: orderedChapterIDs,
                updatedAt: date,
                database: database
            )
            book.updatedAt = date
            try book.update(database)
            try LibrarySearchIndexer.reindexBook(bookID: bookID, database: database)
        }
    }

    func replaceChapterOrder(bookID: UUID, orderedChapterIDs: [UUID]) async throws {
        try await database.write { database in
            let storedIDs = try Self.fetchChapters(forBookID: bookID, database: database).map(\.id)
            guard storedIDs.count == orderedChapterIDs.count,
                  Set(storedIDs) == Set(orderedChapterIDs) else {
                throw LibraryRepositoryError.chapterOrderDoesNotMatchBook
            }
            try Self.setChapterOrder(
                bookID: bookID,
                orderedChapterIDs: orderedChapterIDs,
                updatedAt: nil,
                database: database
            )
            try LibrarySearchIndexer.reindexBook(bookID: bookID, database: database)
        }
    }

    func insertAsset(_ asset: Asset) async throws {
        try await database.write { database in
            try asset.insert(database)
        }
    }

    func insertTag(_ tag: Tag) async throws {
        try await database.write { database in
            try tag.insert(database)
        }
    }

    func linkTag(_ link: BookTag) async throws {
        try await database.write { database in
            try link.insert(database)
            try LibrarySearchIndexer.reindexBook(bookID: link.bookID, database: database)
        }
    }

    func insertReadingProgress(_ progress: ReadingProgress) async throws {
        try await database.write { database in
            try progress.insert(database)
        }
    }

    func insertBookmark(_ bookmark: Bookmark) async throws {
        try await database.write { database in
            try bookmark.insert(database)
        }
    }

    private func removeOwnedStorage(
        bookIDs: [UUID],
        completedAction: String
    ) async throws {
        var failedRemovalCount = 0
        for bookID in bookIDs {
            failedRemovalCount += await assetStore.removeBookStorage(bookID: bookID)
                .failedRemovalCount
        }
        if failedRemovalCount > 0 {
            throw LibraryAssetError.cleanupIncomplete(
                completedAction: completedAction,
                remainingFileCount: failedRemovalCount
            )
        }
    }

    private static func uniqueBookIDs(_ bookIDs: [UUID]) -> [UUID] {
        Array(Set(bookIDs)).sorted { $0.databaseString < $1.databaseString }
    }

    private static func fetchLibraryBooks(_ database: Database) throws -> [LibraryBook] {
        let books = try Book.fetchAll(database)
        let authors = try AuthorshipRow.fetchAll(
            database,
            sql: """
                SELECT bookAuthors.bookID, authors.displayName, bookAuthors.position
                FROM bookAuthors
                JOIN authors ON authors.id = bookAuthors.authorID
                ORDER BY bookAuthors.bookID, bookAuthors.position, authors.normalizedName, authors.id
                """
        )
        let tags = try TaggingRow.fetchAll(
            database,
            sql: """
                SELECT bookTags.bookID, tags.name
                FROM bookTags
                JOIN tags ON tags.id = bookTags.tagID
                ORDER BY bookTags.bookID, tags.normalizedName, tags.id
                """
        )
        let progressRows = try ProgressRow.fetchAll(
            database,
            sql: "SELECT bookID, overallProgress FROM readingProgress"
        )
        let covers = try Asset.fetchAll(
            database,
            sql: "SELECT * FROM assets WHERE purpose = ?",
            arguments: [AssetPurpose.cover.rawValue]
        )

        let authorsByBook = Dictionary(grouping: authors, by: \.bookID)
        let tagsByBook = Dictionary(grouping: tags, by: \.bookID)
        let progressByBook = Dictionary(
            uniqueKeysWithValues: progressRows.map { ($0.bookID, $0.overallProgress) }
        )
        let coversByBook = Dictionary(grouping: covers, by: \.bookID).mapValues { covers in
            covers.sorted {
                if $0.isCurrentCover != $1.isCurrentCover {
                    return $0.isCurrentCover
                }
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt < $1.createdAt
                }
                return $0.id.databaseString < $1.id.databaseString
            }
        }

        return books.map { book in
            let progress = progressByBook[book.id]
            return LibraryBook(
                id: book.id,
                title: book.title,
                subtitle: book.subtitle,
                authors: authorsByBook[book.id, default: []].map(\.displayName),
                summary: book.summary,
                tags: tagsByBook[book.id, default: []].map(\.name),
                dateAdded: book.createdAt,
                isFavorite: book.isFavorite,
                isCurrentlyReading: progress != nil,
                readingProgress: progress,
                isTrashed: book.trashedAt != nil,
                coverAssets: coversByBook[book.id, default: []],
                coverStyle: .derived(from: book.id),
                updatedAt: book.updatedAt,
                lastOpenedAt: book.lastOpenedAt,
                trashedAt: book.trashedAt
            )
        }
    }

    private static func validatedImportedChapters(
        _ chapters: [ImportedBookChapter]
    ) throws -> [ImportedBookChapter] {
        try chapters.map { chapter in
            ImportedBookChapter(
                title: try ChapterTitleInput(title: chapter.title).validated(),
                markdown: chapter.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private static func appendImportedChapters(
        _ importedChapters: [ImportedBookChapter],
        toBookID bookID: UUID,
        at date: Date,
        database: Database
    ) throws {
        let firstPosition = try nextTemporaryChapterPosition(
            bookID: bookID,
            additionalPositionCount: importedChapters.count,
            database: database
        )
        for (offset, importedChapter) in importedChapters.enumerated() {
            try Chapter(
                bookID: bookID,
                title: importedChapter.title,
                markdown: importedChapter.markdown,
                position: firstPosition + offset,
                createdAt: date,
                updatedAt: date
            )
            .insert(database)
        }
    }

    private static func replaceImportedChapters(
        _ importedChapters: [ImportedBookChapter],
        forBookID bookID: UUID,
        at date: Date,
        database: Database
    ) throws {
        let storedChapters = try fetchChapters(forBookID: bookID, database: database)
        var matches = Array<Chapter?>(repeating: nil, count: importedChapters.count)
        var unusedStoredIndices = Set(storedChapters.indices)

        for index in importedChapters.indices where storedChapters.indices.contains(index) {
            if normalizedChapterTitle(storedChapters[index].title)
                == normalizedChapterTitle(importedChapters[index].title) {
                matches[index] = storedChapters[index]
                unusedStoredIndices.remove(index)
            }
        }

        for importedIndex in importedChapters.indices where matches[importedIndex] == nil {
            let normalizedTitle = normalizedChapterTitle(importedChapters[importedIndex].title)
            let matchingStoredIndices = unusedStoredIndices.filter {
                normalizedChapterTitle(storedChapters[$0].title) == normalizedTitle
            }
            let unmatchedImportedCount = importedChapters.indices.filter {
                matches[$0] == nil
                    && normalizedChapterTitle(importedChapters[$0].title) == normalizedTitle
            }
            .count
            if matchingStoredIndices.count == 1, unmatchedImportedCount == 1,
               let storedIndex = matchingStoredIndices.first {
                matches[importedIndex] = storedChapters[storedIndex]
                unusedStoredIndices.remove(storedIndex)
            }
        }

        for importedIndex in importedChapters.indices where matches[importedIndex] == nil {
            guard unusedStoredIndices.contains(importedIndex) else { continue }
            matches[importedIndex] = storedChapters[importedIndex]
            unusedStoredIndices.remove(importedIndex)
        }

        if !storedChapters.isEmpty {
            let temporaryPositionBase = try nextTemporaryChapterPosition(
                bookID: bookID,
                additionalPositionCount: storedChapters.count,
                database: database
            )
            for (offset, chapter) in storedChapters.enumerated() {
                try database.execute(
                    sql: "UPDATE chapters SET position = ? WHERE id = ? AND bookID = ?",
                    arguments: [
                        temporaryPositionBase + offset,
                        chapter.id.databaseString,
                        bookID.databaseString
                    ]
                )
            }
        }

        let retainedIDs = Set(matches.compactMap { $0?.id })
        for storedChapter in storedChapters where !retainedIDs.contains(storedChapter.id) {
            _ = try storedChapter.delete(database)
        }

        for (position, importedChapter) in importedChapters.enumerated() {
            if var chapter = matches[position] {
                if chapter.markdown != importedChapter.markdown {
                    let (nextRevision, overflowed) = chapter.renderRevision.addingReportingOverflow(1)
                    guard !overflowed else {
                        throw LibraryRepositoryError.chapterRevisionLimitReached
                    }
                    chapter.markdown = importedChapter.markdown
                    chapter.renderRevision = nextRevision
                    chapter.sourceHash = nil
                }
                chapter.title = importedChapter.title
                chapter.position = position
                chapter.updatedAt = date
                try chapter.update(database)
            } else {
                try Chapter(
                    bookID: bookID,
                    title: importedChapter.title,
                    markdown: importedChapter.markdown,
                    position: position,
                    createdAt: date,
                    updatedAt: date
                )
                .insert(database)
            }
        }
    }

    private static func normalizedChapterTitle(_ title: String) -> String {
        LibraryNameNormalizer.normalize(title)
    }

    private static func replaceAuthors(
        forBookID bookID: UUID,
        displayNames: [String],
        at date: Date,
        database: Database
    ) throws {
        _ = try BookAuthor
            .filter(Column("bookID") == bookID.databaseString)
            .deleteAll(database)

        for (position, displayName) in displayNames.enumerated() {
            let normalizedName = LibraryNameNormalizer.normalize(displayName)
            let author: Author
            if let existing = try Author
                .filter(Column("normalizedName") == normalizedName)
                .fetchOne(database) {
                author = existing
            } else {
                let newAuthor = Author(
                    displayName: displayName,
                    normalizedName: normalizedName,
                    createdAt: date,
                    updatedAt: date
                )
                try newAuthor.insert(database)
                author = newAuthor
            }

            try BookAuthor(bookID: bookID, authorID: author.id, position: position)
                .insert(database)
        }
    }

    private static func replaceTags(
        forBookID bookID: UUID,
        names: [String],
        at date: Date,
        database: Database
    ) throws {
        _ = try BookTag
            .filter(Column("bookID") == bookID.databaseString)
            .deleteAll(database)

        for name in names {
            let normalizedName = LibraryNameNormalizer.normalize(name)
            let tag: Tag
            if let existing = try Tag
                .filter(Column("normalizedName") == normalizedName)
                .fetchOne(database) {
                tag = existing
            } else {
                let newTag = Tag(
                    name: name,
                    normalizedName: normalizedName,
                    createdAt: date,
                    updatedAt: date
                )
                try newTag.insert(database)
                tag = newTag
            }
            try BookTag(bookID: bookID, tagID: tag.id).insert(database)
        }
    }

    private static func fetchCurrentCover(bookID: UUID, database: Database) throws -> Asset? {
        try Asset.fetchOne(
            database,
            sql: """
                SELECT * FROM assets
                WHERE bookID = ? AND purpose = ? AND isCurrentCover = 1
                """,
            arguments: [bookID.databaseString, AssetPurpose.cover.rawValue]
        )
    }

    private static func fetchCover(
        bookID: UUID,
        coverID: UUID,
        database: Database
    ) throws -> Asset? {
        try Asset.fetchOne(
            database,
            sql: """
                SELECT * FROM assets
                WHERE id = ? AND bookID = ? AND purpose = ?
                """,
            arguments: [
                coverID.databaseString,
                bookID.databaseString,
                AssetPurpose.cover.rawValue,
            ]
        )
    }

    private static func fetchFirstCover(bookID: UUID, database: Database) throws -> Asset? {
        try Asset.fetchOne(
            database,
            sql: """
                SELECT * FROM assets
                WHERE bookID = ? AND purpose = ?
                ORDER BY createdAt, id
                LIMIT 1
                """,
            arguments: [bookID.databaseString, AssetPurpose.cover.rawValue]
        )
    }

    private static func fetchChapters(
        forBookID bookID: UUID,
        database: Database
    ) throws -> [Chapter] {
        try Chapter.fetchAll(
            database,
            sql: """
                SELECT * FROM chapters
                WHERE bookID = ?
                ORDER BY position, id
                """,
            arguments: [bookID.databaseString]
        )
    }

    private static func fetchEditableBook(id: UUID, database: Database) throws -> Book {
        guard let book = try Book.fetchOne(database, key: id.databaseString) else {
            throw LibraryRepositoryError.bookNotFound
        }
        guard book.trashedAt == nil else {
            throw LibraryRepositoryError.bookIsInTrash
        }
        return book
    }

    private static func nextTemporaryChapterPosition(
        bookID: UUID,
        additionalPositionCount: Int,
        database: Database
    ) throws -> Int {
        let maximumPosition = try Int.fetchOne(
            database,
            sql: "SELECT MAX(position) FROM chapters WHERE bookID = ?",
            arguments: [bookID.databaseString]
        ) ?? -1
        let (nextPosition, nextOverflowed) = maximumPosition.addingReportingOverflow(1)
        let (_, rangeOverflowed) = nextPosition.addingReportingOverflow(additionalPositionCount)
        guard !nextOverflowed, !rangeOverflowed else {
            throw LibraryRepositoryError.chapterPositionLimitReached
        }
        return nextPosition
    }

    private static func setChapterOrder(
        bookID: UUID,
        orderedChapterIDs: [UUID],
        updatedAt date: Date?,
        database: Database
    ) throws {
        guard !orderedChapterIDs.isEmpty else { return }
        let temporaryPositionBase = try nextTemporaryChapterPosition(
            bookID: bookID,
            additionalPositionCount: orderedChapterIDs.count,
            database: database
        )

        for (offset, chapterID) in orderedChapterIDs.enumerated() {
            try database.execute(
                sql: "UPDATE chapters SET position = ? WHERE id = ? AND bookID = ?",
                arguments: [
                    temporaryPositionBase + offset,
                    chapterID.databaseString,
                    bookID.databaseString
                ]
            )
            guard database.changesCount == 1 else {
                throw LibraryRepositoryError.chapterOrderDoesNotMatchBook
            }
        }

        for (position, chapterID) in orderedChapterIDs.enumerated() {
            guard var chapter = try Chapter.fetchOne(database, key: chapterID.databaseString),
                  chapter.bookID == bookID else {
                throw LibraryRepositoryError.chapterOrderDoesNotMatchBook
            }
            chapter.position = position
            if let date {
                chapter.updatedAt = date
            }
            try chapter.update(database)
        }
    }
}

private nonisolated struct LibrarySearchRow: Decodable, FetchableRecord, Sendable {
    let documentKey: String
    let bookID: UUID
    let bookTitle: String
    let authorLine: String
    let chapterID: UUID?
    let storedChapterTitle: String?
    let stableBlockID: String?
    let fractionInChapter: Double
    let kind: LibrarySearchResultKind
    let body: String
    let highlightedTitle: String
    let highlightedSubtitle: String
    let highlightedAuthors: String
    let highlightedTags: String
    let highlightedChapterTitle: String
    let bodySnippet: String

    var searchResult: LibrarySearchResult {
        let candidates: [String]
        switch kind {
        case .metadata:
            candidates = [
                highlightedTitle,
                highlightedSubtitle,
                highlightedAuthors,
                highlightedTags
            ]
        case .chapterTitle:
            candidates = [highlightedChapterTitle]
        case .content:
            candidates = [bodySnippet]
        }
        let snippet = candidates.first {
            $0.contains(LibrarySearchIndexer.highlightStart)
        } ?? candidates.first(where: { !$0.isEmpty }) ?? bookTitle

        return LibrarySearchResult(
            id: documentKey,
            bookID: bookID,
            bookTitle: bookTitle,
            authorLine: authorLine,
            chapterID: chapterID,
            chapterTitle: storedChapterTitle,
            stableBlockID: stableBlockID,
            textQuote: body.isEmpty ? nil : String(body.prefix(220)),
            fractionInChapter: fractionInChapter,
            kind: kind,
            highlightedSnippet: snippet
        )
    }
}

private nonisolated struct AuthorshipRow: Decodable, FetchableRecord, Sendable {
    let bookID: UUID
    let displayName: String
    let position: Int
}

private nonisolated struct TaggingRow: Decodable, FetchableRecord, Sendable {
    let bookID: UUID
    let name: String
}

private nonisolated struct ProgressRow: Decodable, FetchableRecord, Sendable {
    let bookID: UUID
    let overallProgress: Double
}

#if DEBUG
extension GRDBLibraryRepository {
    @discardableResult
    func seedSampleLibrary(referenceDate: Date = .now) async throws -> Bool {
        try await database.write { database in
            guard try Book.fetchCount(database) == 0 else {
                return false
            }

            var authorsByName: [String: Author] = [:]
            var tagsByName: [String: Tag] = [:]

            for definition in SampleLibrary.definitions {
                let addedAt = SampleLibrary.date(
                    daysBefore: definition.daysBeforeAdded,
                    referenceDate: referenceDate
                )
                let book = Book(
                    title: definition.title,
                    subtitle: definition.subtitle,
                    summary: definition.summary,
                    isFavorite: definition.isFavorite,
                    createdAt: addedAt,
                    updatedAt: addedAt
                )
                try book.insert(database)

                for (position, displayName) in definition.authors.enumerated() {
                    let normalizedName = LibraryNameNormalizer.normalize(displayName)
                    let author: Author
                    if let existing = authorsByName[normalizedName] {
                        author = existing
                    } else {
                        let newAuthor = Author(
                            displayName: displayName,
                            normalizedName: normalizedName,
                            createdAt: addedAt,
                            updatedAt: addedAt
                        )
                        try newAuthor.insert(database)
                        authorsByName[normalizedName] = newAuthor
                        author = newAuthor
                    }
                    try BookAuthor(bookID: book.id, authorID: author.id, position: position)
                        .insert(database)
                }

                for tagName in definition.tags {
                    let normalizedName = LibraryNameNormalizer.normalize(tagName)
                    let tag: Tag
                    if let existing = tagsByName[normalizedName] {
                        tag = existing
                    } else {
                        let newTag = Tag(
                            name: tagName,
                            normalizedName: normalizedName,
                            createdAt: addedAt,
                            updatedAt: addedAt
                        )
                        try newTag.insert(database)
                        tagsByName[normalizedName] = newTag
                        tag = newTag
                    }
                    try BookTag(bookID: book.id, tagID: tag.id).insert(database)
                }

                if let progress = definition.readingProgress {
                    try ReadingProgress(
                        bookID: book.id,
                        chapterID: nil,
                        stableBlockID: nil,
                        textQuote: nil,
                        contextBefore: nil,
                        contextAfter: nil,
                        fractionInChapter: nil,
                        overallProgress: progress,
                        lastReadAt: addedAt
                    )
                    .insert(database)
                }
            }

            _ = try LibrarySearchIndexer.rebuildAll(database)

            return true
        }
    }

    func resetSampleLibrary() async throws {
        try await database.write { database in
            try database.execute(sql: "DELETE FROM books")
            try database.execute(sql: "DELETE FROM authors")
            try database.execute(sql: "DELETE FROM tags")
        }

        let report = await assetStore.repair(referencedAssets: [])
        if report.failedRemovalCount > 0 {
            throw LibraryAssetError.cleanupIncomplete(
                completedAction: "The sample library was reset",
                remainingFileCount: report.failedRemovalCount
            )
        }
    }
}
#endif
