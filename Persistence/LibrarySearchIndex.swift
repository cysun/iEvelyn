import Foundation
import GRDB

nonisolated enum LibrarySearchIndexer {
    static let documentTable = "librarySearchDocuments"
    static let indexTable = "librarySearchIndex"
    static let highlightStart = "\u{E000}"
    static let highlightEnd = "\u{E001}"

    static func rebuildAll(_ database: Database) throws -> LibrarySearchRepairReport {
        let previousDocumentCount = try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM \(documentTable)"
        ) ?? 0
        try database.execute(sql: "DELETE FROM \(documentTable)")

        let bookIDs = try UUID.fetchAll(
            database,
            sql: "SELECT id FROM books ORDER BY id"
        )
        for bookID in bookIDs {
            try reindexBook(bookID: bookID, database: database)
        }

        let rebuiltDocumentCount = try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM \(documentTable)"
        ) ?? 0
        return LibrarySearchRepairReport(
            previousDocumentCount: previousDocumentCount,
            rebuiltDocumentCount: rebuiltDocumentCount,
            indexedBookCount: bookIDs.count
        )
    }

    static func reindexBook(bookID: UUID, database: Database) throws {
        try database.execute(
            sql: "DELETE FROM \(documentTable) WHERE bookID = ?",
            arguments: [bookID.databaseString]
        )
        guard let book = try Book.fetchOne(database, key: bookID.databaseString) else {
            return
        }

        let authors = try String.fetchAll(
            database,
            sql: """
                SELECT authors.displayName
                FROM authors
                JOIN bookAuthors ON bookAuthors.authorID = authors.id
                WHERE bookAuthors.bookID = ?
                ORDER BY bookAuthors.position, authors.normalizedName, authors.id
                """,
            arguments: [bookID.databaseString]
        )
        let tags = try String.fetchAll(
            database,
            sql: """
                SELECT tags.name
                FROM tags
                JOIN bookTags ON bookTags.tagID = tags.id
                WHERE bookTags.bookID = ?
                ORDER BY tags.normalizedName, tags.id
                """,
            arguments: [bookID.databaseString]
        )

        try insertDocument(
            database: database,
            documentKey: "book:\(bookID.databaseString):metadata",
            bookID: bookID,
            chapterID: nil,
            stableBlockID: nil,
            kind: .metadata,
            ordinal: 0,
            fractionInChapter: 0,
            title: book.title,
            subtitle: book.subtitle ?? "",
            authors: authors.joined(separator: ", "),
            tags: tags.joined(separator: ", "),
            chapterTitle: "",
            body: ""
        )

        let chapters = try Chapter.fetchAll(
            database,
            sql: """
                SELECT * FROM chapters
                WHERE bookID = ?
                ORDER BY position, id
                """,
            arguments: [bookID.databaseString]
        )
        for chapter in chapters {
            try insertDocument(
                database: database,
                documentKey: "chapter:\(chapter.id.databaseString):title",
                bookID: bookID,
                chapterID: chapter.id,
                stableBlockID: nil,
                kind: .chapterTitle,
                ordinal: chapter.position,
                fractionInChapter: 0,
                title: "",
                subtitle: "",
                authors: "",
                tags: "",
                chapterTitle: chapter.title,
                body: ""
            )

            let blocks = MarkdownSearchTextExtractor.blocks(from: chapter.markdown)
            let denominator = max(1, blocks.count - 1)
            for (blockOrdinal, block) in blocks.enumerated() where !block.normalizedText.isEmpty {
                try insertDocument(
                    database: database,
                    documentKey: "chapter:\(chapter.id.databaseString):\(block.id)",
                    bookID: bookID,
                    chapterID: chapter.id,
                    stableBlockID: block.id,
                    kind: .content,
                    ordinal: blockOrdinal,
                    fractionInChapter: Double(blockOrdinal) / Double(denominator),
                    title: "",
                    subtitle: "",
                    authors: "",
                    tags: "",
                    chapterTitle: "",
                    body: block.normalizedText
                )
            }
        }
    }

    private static func insertDocument(
        database: Database,
        documentKey: String,
        bookID: UUID,
        chapterID: UUID?,
        stableBlockID: String?,
        kind: LibrarySearchResultKind,
        ordinal: Int,
        fractionInChapter: Double,
        title: String,
        subtitle: String,
        authors: String,
        tags: String,
        chapterTitle: String,
        body: String
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO \(documentTable) (
                    documentKey, bookID, chapterID, stableBlockID, kind, ordinal,
                    fractionInChapter, title, subtitle, authors, tags, chapterTitle, body
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                documentKey,
                bookID.databaseString,
                chapterID?.databaseString,
                stableBlockID,
                kind.rawValue,
                ordinal,
                fractionInChapter,
                title,
                subtitle,
                authors,
                tags,
                chapterTitle,
                body
            ]
        )
    }
}

nonisolated enum LibrarySearchQueryBuilder {
    static func matchExpression(for query: String, scope: LibrarySearchScope) throws -> String {
        let terms = query
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
            .compactMap(phraseExpression)
        guard !terms.isEmpty else {
            throw LibrarySearchError.invalidQuery
        }

        let expression = terms.joined(separator: " AND ")
        guard let columnFilter = scope.columnFilter else {
            return expression
        }
        return "\(columnFilter) : (\(expression))"
    }

    private static func phraseExpression(_ value: String) -> String? {
        let tokens = SimpleNoPinyinQueryTokenizer.tokens(in: value)
        guard !tokens.isEmpty else { return nil }
        return tokens.map(quoted).joined(separator: " + ")
    }

    private static func quoted(_ token: String) -> String {
        "\"\(token.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private nonisolated enum SimpleNoPinyinQueryTokenizer {
    private enum Category {
        case space
        case asciiAlphabetic
        case digit
        case other
    }

    static func tokens(in value: String) -> [String] {
        let bytes = Array(value.utf8)
        var result: [String] = []
        var start = 0
        var index = 0
        while index < bytes.count {
            let tokenCategory = category(bytes[index])
            switch tokenCategory {
            case .other:
                index = min(bytes.count, index + utf8Length(bytes[index]))
            default:
                index += 1
                while index < bytes.count, category(bytes[index]) == tokenCategory {
                    index += 1
                }
            }

            if tokenCategory != .space {
                var tokenBytes = Array(bytes[start..<index])
                if tokenCategory == .asciiAlphabetic {
                    tokenBytes = tokenBytes.map { byte in
                        (65...90).contains(byte) ? byte + 32 : byte
                    }
                }
                if let token = String(bytes: tokenBytes, encoding: .utf8) {
                    result.append(token)
                }
            }
            start = index
        }
        return result
    }

    private static func category(_ byte: UInt8) -> Category {
        if byte > 127 { return .other }
        if (48...57).contains(byte) { return .digit }
        if byte <= 32 || byte == 127 { return .space }
        if (65...90).contains(byte) || (97...122).contains(byte) {
            return .asciiAlphabetic
        }
        return .other
    }

    private static func utf8Length(_ byte: UInt8) -> Int {
        if byte >= 0xF0 { return 4 }
        if byte >= 0xE0 { return 3 }
        if byte >= 0xC0 { return 2 }
        return 1
    }
}

private extension LibrarySearchScope {
    nonisolated var columnFilter: String? {
        switch self {
        case .all:
            nil
        case .titles:
            "{title subtitle}"
        case .authors:
            "authors"
        case .tags:
            "tags"
        case .chapterTitles:
            "chapterTitle"
        case .content:
            "body"
        }
    }
}
