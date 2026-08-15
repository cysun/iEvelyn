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
}

nonisolated enum LibraryRepositoryError: LocalizedError, Equatable {
    case chapterOrderDoesNotMatchBook
    case bookNotFound
    case permanentDeleteRequiresTrash
    case readOnlyRepository

    var errorDescription: String? {
        switch self {
        case .chapterOrderDoesNotMatchBook:
            "The chapter order must contain every chapter in the book exactly once."
        case .bookNotFound:
            "The selected book no longer exists."
        case .permanentDeleteRequiresTrash:
            "Move the book to Trash before deleting it permanently."
        case .readOnlyRepository:
            "This library is read-only."
        }
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
}

nonisolated final class GRDBLibraryRepository: LibraryRepository, Sendable {
    let database: LibraryDatabase

    init(database: LibraryDatabase) {
        self.database = database
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

    func fetchLibraryBooks() async throws -> [LibraryBook] {
        try await database.read(Self.fetchLibraryBooks)
    }

    func createBook(metadata: BookMetadataInput, at date: Date = .now) async throws -> UUID {
        let metadata = try metadata.validated()
        let book = Book(
            title: metadata.title,
            subtitle: metadata.subtitle,
            summary: metadata.summary,
            languageCode: metadata.languageCode,
            publisher: metadata.publisher,
            publicationDate: metadata.publicationDate,
            createdAt: date,
            updatedAt: date,
            lastOpenedAt: date
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
            book.languageCode = metadata.languageCode
            book.publisher = metadata.publisher
            book.publicationDate = metadata.publicationDate
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
    }

    func replaceChapterOrder(bookID: UUID, orderedChapterIDs: [UUID]) async throws {
        try await database.write { database in
            let storedIDs = try UUID.fetchAll(
                database,
                sql: "SELECT id FROM chapters WHERE bookID = ?",
                arguments: [bookID.databaseString]
            )
            guard storedIDs.count == orderedChapterIDs.count,
                  Set(storedIDs) == Set(orderedChapterIDs) else {
                throw LibraryRepositoryError.chapterOrderDoesNotMatchBook
            }

            let temporaryPositionBase = Int.max - orderedChapterIDs.count
            for (offset, chapterID) in orderedChapterIDs.enumerated() {
                try database.execute(
                    sql: "UPDATE chapters SET position = ? WHERE id = ? AND bookID = ?",
                    arguments: [temporaryPositionBase + offset, chapterID.databaseString, bookID.databaseString]
                )
            }

            for (position, chapterID) in orderedChapterIDs.enumerated() {
                try database.execute(
                    sql: "UPDATE chapters SET position = ? WHERE id = ? AND bookID = ?",
                    arguments: [position, chapterID.databaseString, bookID.databaseString]
                )
            }
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

        let authorsByBook = Dictionary(grouping: authors, by: \.bookID)
        let tagsByBook = Dictionary(grouping: tags, by: \.bookID)
        let progressByBook = Dictionary(
            uniqueKeysWithValues: progressRows.map { ($0.bookID, $0.overallProgress) }
        )

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
                coverStyle: .derived(from: book.id),
                languageCode: book.languageCode,
                publisher: book.publisher,
                publicationDate: book.publicationDate,
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
    }
}
#endif
