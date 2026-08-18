import Foundation

nonisolated struct Book: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var subtitle: String?
    var summary: String
    var isFavorite: Bool
    var trashedAt: Date?
    let createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        summary: String = "",
        isFavorite: Bool = false,
        trashedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastOpenedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.summary = summary
        self.isFavorite = isFavorite
        self.trashedAt = trashedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
    }
}

nonisolated struct BookMetadataInput: Equatable, Sendable {
    var title: String
    var subtitle: String
    var authors: [String]
    var tags: [String]
    var summary: String

    static let empty = BookMetadataInput(
        title: "",
        subtitle: "",
        authors: [""],
        tags: [],
        summary: ""
    )

    init(
        title: String,
        subtitle: String = "",
        authors: [String],
        tags: [String] = [],
        summary: String = ""
    ) {
        self.title = title
        self.subtitle = subtitle
        self.authors = authors
        self.tags = tags
        self.summary = summary
    }

    func validated() throws -> ValidatedBookMetadata {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw BookMetadataValidationError.titleRequired
        }

        let authors = authors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !authors.isEmpty, authors.allSatisfy({ !$0.isEmpty }) else {
            throw BookMetadataValidationError.authorRequired
        }

        var normalizedAuthors = Set<String>()
        for author in authors {
            let normalizedName = LibraryNameNormalizer.normalize(author)
            guard normalizedAuthors.insert(normalizedName).inserted else {
                throw BookMetadataValidationError.duplicateAuthor(author)
            }
        }

        let tags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard tags.allSatisfy({ !$0.isEmpty }) else {
            throw BookMetadataValidationError.emptyTag
        }
        var normalizedTags = Set<String>()
        for tag in tags {
            let normalizedName = LibraryNameNormalizer.normalize(tag)
            guard normalizedTags.insert(normalizedName).inserted else {
                throw BookMetadataValidationError.duplicateTag(tag)
            }
        }

        return ValidatedBookMetadata(
            title: title,
            subtitle: Self.optionalTrimmed(subtitle),
            authors: authors,
            tags: tags,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func optionalTrimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

}

nonisolated struct ValidatedBookMetadata: Equatable, Sendable {
    let title: String
    let subtitle: String?
    let authors: [String]
    let tags: [String]
    let summary: String
}

nonisolated enum BookMetadataValidationError: LocalizedError, Equatable {
    case titleRequired
    case authorRequired
    case duplicateAuthor(String)
    case emptyTag
    case duplicateTag(String)

    var errorDescription: String? {
        switch self {
        case .titleRequired:
            "Enter a title."
        case .authorRequired:
            "Enter at least one author, and remove any empty author rows."
        case .duplicateAuthor(let name):
            "Each author may appear only once. “\(name)” is duplicated."
        case .emptyTag:
            "Remove any empty tag rows."
        case .duplicateTag(let name):
            "Each tag may appear only once. “\(name)” is duplicated."
        }
    }
}

nonisolated struct Author: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    var normalizedName: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        normalizedName: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.normalizedName = normalizedName ?? LibraryNameNormalizer.normalize(displayName)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct BookAuthor: Codable, Equatable, Sendable {
    let bookID: UUID
    let authorID: UUID
    var position: Int
}

nonisolated struct Chapter: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let bookID: UUID
    var title: String
    var markdown: String
    var position: Int
    var renderRevision: Int
    var sourceHash: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        title: String,
        markdown: String = "",
        position: Int,
        renderRevision: Int = 0,
        sourceHash: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.bookID = bookID
        self.title = title
        self.markdown = markdown
        self.position = position
        self.renderRevision = renderRevision
        self.sourceHash = sourceHash
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Chapter {
    nonisolated var wordCount: Int {
        ChapterTextMetrics.wordCount(in: markdown)
    }
}

nonisolated struct ChapterTextMetrics: Equatable, Sendable {
    let wordCount: Int
    let characterCount: Int

    init(markdown: String) {
        wordCount = Self.wordCount(in: markdown)
        characterCount = markdown.count
    }

    static let zero = ChapterTextMetrics(markdown: "")

    fileprivate static func wordCount(in markdown: String) -> Int {
        markdown.split { character in
            guard !character.isLetter, !character.isNumber else { return false }
            return character != "'" && character != "’"
        }
        .count
    }
}

nonisolated struct ChapterTitleInput: Equatable, Sendable {
    var title: String

    func validated() throws -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw ChapterValidationError.titleRequired
        }
        return trimmedTitle
    }
}

nonisolated enum ChapterValidationError: LocalizedError, Equatable {
    case titleRequired

    var errorDescription: String? {
        switch self {
        case .titleRequired:
            "Enter a chapter title."
        }
    }
}

nonisolated struct ChapterCollectionSummary: Equatable, Sendable {
    let chapterCount: Int
    let wordCount: Int

    init(chapters: [Chapter]) {
        chapterCount = chapters.count
        wordCount = chapters.reduce(into: 0) { count, chapter in
            count += chapter.wordCount
        }
    }
}

/// A transaction snapshot retained only while chapter-deletion undo is available.
nonisolated struct ChapterDeletion: Equatable, Sendable {
    let chapter: Chapter
    let linkedAssetIDs: [UUID]
    let hadLinkedReadingProgress: Bool
    let linkedBookmarkIDs: [UUID]
}

nonisolated enum AssetPurpose: String, Codable, CaseIterable, Sendable {
    case cover
    case chapterImage
    case attachment
}

nonisolated struct Asset: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let bookID: UUID
    var chapterID: UUID?
    var purpose: AssetPurpose
    var mediaType: String
    var storageRelativePath: String
    var checksum: String
    var byteCount: Int64
    var pixelWidth: Int?
    var pixelHeight: Int?
    var isCurrentCover: Bool
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        chapterID: UUID? = nil,
        purpose: AssetPurpose,
        mediaType: String,
        storageRelativePath: String,
        checksum: String,
        byteCount: Int64,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        isCurrentCover: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.bookID = bookID
        self.chapterID = chapterID
        self.purpose = purpose
        self.mediaType = mediaType
        self.storageRelativePath = storageRelativePath
        self.checksum = checksum
        self.byteCount = byteCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isCurrentCover = isCurrentCover
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct Tag: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var normalizedName: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        normalizedName: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.normalizedName = normalizedName ?? LibraryNameNormalizer.normalize(name)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct BookTag: Codable, Equatable, Sendable {
    let bookID: UUID
    let tagID: UUID
}

nonisolated struct ReadingProgress: Codable, Equatable, Sendable {
    let bookID: UUID
    var chapterID: UUID?
    var stableBlockID: String?
    var textQuote: String?
    var contextBefore: String?
    var contextAfter: String?
    var fractionInChapter: Double?
    var overallProgress: Double
    var lastReadAt: Date
}

nonisolated struct Bookmark: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let bookID: UUID
    var chapterID: UUID?
    var stableBlockID: String?
    var textQuote: String?
    var contextBefore: String?
    var contextAfter: String?
    var fractionInChapter: Double?
    var label: String?
    var note: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        chapterID: UUID? = nil,
        stableBlockID: String? = nil,
        textQuote: String? = nil,
        contextBefore: String? = nil,
        contextAfter: String? = nil,
        fractionInChapter: Double? = nil,
        label: String? = nil,
        note: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.bookID = bookID
        self.chapterID = chapterID
        self.stableBlockID = stableBlockID
        self.textQuote = textQuote
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.fractionInChapter = fractionInChapter
        self.label = label
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated enum LibraryNameNormalizer {
    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
}
