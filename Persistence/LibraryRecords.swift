import Foundation
import GRDB

nonisolated protocol LibraryRecord: Codable, FetchableRecord, PersistableRecord, TableRecord, Sendable { }

extension LibraryRecord {
    nonisolated static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .millisecondsSince1970
    }

    nonisolated static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .millisecondsSince1970
    }

    nonisolated static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy {
        .lowercaseString
    }
}

extension UUID {
    nonisolated var databaseString: String {
        uuidString.lowercased()
    }
}

extension Book: nonisolated LibraryRecord {
    static let databaseTableName = "books"
}

extension Author: nonisolated LibraryRecord {
    static let databaseTableName = "authors"
}

extension BookAuthor: nonisolated LibraryRecord {
    static let databaseTableName = "bookAuthors"
}

extension Chapter: nonisolated LibraryRecord {
    static let databaseTableName = "chapters"
}

extension Asset: nonisolated LibraryRecord {
    static let databaseTableName = "assets"
}

extension Tag: nonisolated LibraryRecord {
    static let databaseTableName = "tags"
}

extension BookTag: nonisolated LibraryRecord {
    static let databaseTableName = "bookTags"
}

extension ReadingProgress: nonisolated LibraryRecord {
    static let databaseTableName = "readingProgress"
}

extension Bookmark: nonisolated LibraryRecord {
    static let databaseTableName = "bookmarks"
}
