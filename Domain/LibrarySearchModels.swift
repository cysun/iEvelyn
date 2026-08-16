import Foundation

nonisolated enum LibrarySearchScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case titles
    case authors
    case tags
    case chapterTitles
    case content

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            "All Fields"
        case .titles:
            "Book Titles"
        case .authors:
            "Authors"
        case .tags:
            "Tags"
        case .chapterTitles:
            "Chapter Titles"
        case .content:
            "Book Content"
        }
    }
}

nonisolated enum LibrarySearchTrashScope: String, Sendable {
    case activeLibrary
    case trash
}

nonisolated enum LibrarySearchResultKind: String, Codable, Sendable {
    case metadata
    case chapterTitle
    case content
}

nonisolated struct LibrarySearchResult: Identifiable, Equatable, Sendable {
    let id: String
    let bookID: UUID
    let bookTitle: String
    let authorLine: String
    let chapterID: UUID?
    let chapterTitle: String?
    let stableBlockID: String?
    let textQuote: String?
    let fractionInChapter: Double
    let kind: LibrarySearchResultKind
    let highlightedSnippet: String
}

nonisolated struct LibrarySearchRepairReport: Equatable, Sendable {
    let previousDocumentCount: Int
    let rebuiltDocumentCount: Int
    let indexedBookCount: Int
}

nonisolated struct LibraryOrganizationGroup: Identifiable, Equatable, Sendable {
    let name: String
    let bookIDs: Set<UUID>

    var id: String { LibraryNameNormalizer.normalize(name) }
    var bookCount: Int { bookIDs.count }
}

nonisolated enum LibrarySearchError: LocalizedError, Equatable {
    case tokenizerRegistrationFailed(code: Int32)
    case invalidQuery

    var errorDescription: String? {
        switch self {
        case .tokenizerRegistrationFailed(let code):
            "The Chinese search tokenizer could not be registered with SQLite (code: \(code))."
        case .invalidQuery:
            "Enter at least one searchable character."
        }
    }
}
