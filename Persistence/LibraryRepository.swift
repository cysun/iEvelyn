import Foundation
import GRDB

nonisolated protocol LibraryRepository: Sendable {
    func observeLibraryBooks() -> AsyncThrowingStream<[LibraryBook], Error>
}

nonisolated enum LibraryRepositoryError: LocalizedError, Equatable {
    case chapterOrderDoesNotMatchBook

    var errorDescription: String? {
        switch self {
        case .chapterOrderDoesNotMatchBook:
            "The chapter order must contain every chapter in the book exactly once."
        }
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
            _ = try Book.deleteOne(database, key: id.databaseString)
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
                coverStyle: .derived(from: book.id)
            )
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
