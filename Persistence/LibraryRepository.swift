import Foundation
import GRDB

nonisolated protocol LibraryRepository: Sendable {
    func observeLibraryBooks() -> AsyncThrowingStream<[LibraryBook], Error>
    func createBook(metadata: BookMetadataInput, at date: Date) async throws -> UUID
    func updateBook(id: UUID, metadata: BookMetadataInput, at date: Date) async throws
    func setFavorite(bookID: UUID, isFavorite: Bool, at date: Date) async throws
    func moveBookToTrash(id: UUID, at date: Date) async throws
    func restoreBook(id: UUID, at date: Date) async throws
    func markBookOpened(id: UUID, at date: Date) async throws
    func deleteBookPermanently(id: UUID) async throws
    func importCover(bookID: UUID, from sourceURL: URL, at date: Date) async throws
    func removeCover(bookID: UUID, at date: Date) async throws
    func coverThumbnailData(for asset: Asset) async throws -> Data
    func observeChapters(forBookID bookID: UUID) -> AsyncThrowingStream<[Chapter], Error>
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
    case bookNotFound
    case bookIsInTrash
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
        case .bookNotFound:
            "The selected book no longer exists."
        case .bookIsInTrash:
            "Restore the book before changing its chapters."
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
    func createBook(metadata: BookMetadataInput, at date: Date) async throws -> UUID {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func updateBook(id: UUID, metadata: BookMetadataInput, at date: Date) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func setFavorite(bookID: UUID, isFavorite: Bool, at date: Date) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func moveBookToTrash(id: UUID, at date: Date) async throws {
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

    func importCover(bookID: UUID, from sourceURL: URL, at date: Date) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func removeCover(bookID: UUID, at date: Date) async throws {
        throw LibraryRepositoryError.readOnlyRepository
    }

    func coverThumbnailData(for asset: Asset) async throws -> Data {
        throw LibraryRepositoryError.readOnlyRepository
    }

    nonisolated func observeChapters(forBookID bookID: UUID) -> AsyncThrowingStream<[Chapter], Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: LibraryRepositoryError.readOnlyRepository)
        }
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
        let observation = ValueObservation.tracking { database in
            try Self.fetchLibraryBooks(database)
        }
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
        }
    }

    func updateBook(_ book: Book) async throws {
        try await database.write { database in
            try book.update(database)
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

    func importCover(
        bookID: UUID,
        from sourceURL: URL,
        at date: Date = .now
    ) async throws {
        let preparedAsset = try await assetStore.prepareCoverImport(
            bookID: bookID,
            sourceURL: sourceURL,
            at: date
        )

        let previousCover: Asset?
        do {
            previousCover = try await database.write { database in
                guard var book = try Book.fetchOne(database, key: bookID.databaseString) else {
                    throw LibraryRepositoryError.bookNotFound
                }

                let previousCover = try Self.fetchCover(bookID: bookID, database: database)
                if let previousCover {
                    _ = try previousCover.delete(database)
                }
                try preparedAsset.asset.insert(database)

                book.updatedAt = date
                try book.update(database)
                return previousCover
            }
        } catch {
            _ = await assetStore.discardPreparedAsset(preparedAsset)
            throw error
        }

        if let previousCover {
            let report = await assetStore.removeFiles(for: [previousCover])
            if report.failedRemovalCount > 0 {
                throw LibraryAssetError.cleanupIncomplete(
                    completedAction: "The cover was replaced",
                    remainingFileCount: report.failedRemovalCount
                )
            }
        }
    }

    func removeCover(bookID: UUID, at date: Date = .now) async throws {
        let previousCover = try await database.write { database in
            guard var book = try Book.fetchOne(database, key: bookID.databaseString) else {
                throw LibraryRepositoryError.bookNotFound
            }
            guard let previousCover = try Self.fetchCover(bookID: bookID, database: database) else {
                return nil as Asset?
            }

            _ = try previousCover.delete(database)
            book.updatedAt = date
            try book.update(database)
            return previousCover
        }

        guard let previousCover else { return }
        let report = await assetStore.removeFiles(for: [previousCover])
        if report.failedRemovalCount > 0 {
            throw LibraryAssetError.cleanupIncomplete(
                completedAction: "The cover was removed",
                remainingFileCount: report.failedRemovalCount
            )
        }
    }

    func coverThumbnailData(for asset: Asset) async throws -> Data {
        try await assetStore.thumbnailData(for: asset)
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
        let coverByBook = Dictionary(uniqueKeysWithValues: covers.map { ($0.bookID, $0) })

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
                coverAsset: coverByBook[book.id],
                coverStyle: .derived(from: book.id),
                updatedAt: book.updatedAt,
                lastOpenedAt: book.lastOpenedAt,
                trashedAt: book.trashedAt
            )
        }
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

    private static func fetchCover(bookID: UUID, database: Database) throws -> Asset? {
        try Asset.fetchOne(
            database,
            sql: "SELECT * FROM assets WHERE bookID = ? AND purpose = ?",
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
