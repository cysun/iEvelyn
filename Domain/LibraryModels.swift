import Foundation

nonisolated struct Book: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var subtitle: String?
    var summary: String
    var languageCode: String
    var publisher: String?
    var publicationDate: Date?
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
        languageCode: String = "en",
        publisher: String? = nil,
        publicationDate: Date? = nil,
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
        self.languageCode = languageCode
        self.publisher = publisher
        self.publicationDate = publicationDate
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
    var summary: String
    var languageCode: String
    var publisher: String
    var publicationDate: Date?

    static let empty = BookMetadataInput(
        title: "",
        subtitle: "",
        authors: [""],
        summary: "",
        languageCode: "en",
        publisher: "",
        publicationDate: nil
    )

    init(
        title: String,
        subtitle: String = "",
        authors: [String],
        summary: String = "",
        languageCode: String = "en",
        publisher: String = "",
        publicationDate: Date? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.authors = authors
        self.summary = summary
        self.languageCode = languageCode
        self.publisher = publisher
        self.publicationDate = publicationDate
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

        let languageCode = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidLanguageCode(languageCode) else {
            throw BookMetadataValidationError.invalidLanguageCode
        }

        return ValidatedBookMetadata(
            title: title,
            subtitle: Self.optionalTrimmed(subtitle),
            authors: authors,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            languageCode: languageCode,
            publisher: Self.optionalTrimmed(publisher),
            publicationDate: publicationDate
        )
    }

    private static func optionalTrimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isValidLanguageCode(_ value: String) -> Bool {
        guard (2...15).contains(value.count) else { return false }

        let segments = value.split(separator: "-", omittingEmptySubsequences: false)
        guard let first = segments.first,
              (2...8).contains(first.count),
              first.allSatisfy(\.isASCIIEnglishLetter) else {
            return false
        }

        return segments.dropFirst().allSatisfy { segment in
            (1...8).contains(segment.count) && segment.allSatisfy(\.isASCIIEnglishLetterOrNumber)
        }
    }
}

nonisolated struct ValidatedBookMetadata: Equatable, Sendable {
    let title: String
    let subtitle: String?
    let authors: [String]
    let summary: String
    let languageCode: String
    let publisher: String?
    let publicationDate: Date?
}

nonisolated enum BookMetadataValidationError: LocalizedError, Equatable {
    case titleRequired
    case authorRequired
    case duplicateAuthor(String)
    case invalidLanguageCode

    var errorDescription: String? {
        switch self {
        case .titleRequired:
            "Enter a title."
        case .authorRequired:
            "Enter at least one author, and remove any empty author rows."
        case .duplicateAuthor(let name):
            "Each author may appear only once. “\(name)” is duplicated."
        case .invalidLanguageCode:
            "Enter a language code such as en, en-US, or zh-Hant."
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

nonisolated enum AssetPurpose: String, Codable, CaseIterable, Sendable {
    case cover
    case chapterImage
    case attachment
}

nonisolated struct Asset: Codable, Identifiable, Equatable, Sendable {
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

private extension Character {
    nonisolated var isASCIIEnglishLetter: Bool {
        unicodeScalars.count == 1 && unicodeScalars.allSatisfy { scalar in
            (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
        }
    }

    nonisolated var isASCIIEnglishLetterOrNumber: Bool {
        isASCIIEnglishLetter || unicodeScalars.allSatisfy { scalar in
            unicodeScalars.count == 1 && (48...57).contains(scalar.value)
        }
    }
}
