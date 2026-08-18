import Foundation

/// A read-only library projection assembled from normalized persisted records.
nonisolated struct LibraryBook: Identifiable, Hashable, Sendable {
    typealias ID = UUID

    let id: ID
    let title: String
    let subtitle: String?
    let authors: [String]
    let summary: String
    let tags: [String]
    let dateAdded: Date
    let isFavorite: Bool
    let isCurrentlyReading: Bool
    let readingProgress: Double?
    let isTrashed: Bool
    let coverAssets: [Asset]
    let coverStyle: BookCoverStyle
    let updatedAt: Date
    let lastOpenedAt: Date?
    let trashedAt: Date?

    init(
        id: ID,
        title: String,
        subtitle: String?,
        authors: [String],
        summary: String,
        tags: [String],
        dateAdded: Date,
        isFavorite: Bool,
        isCurrentlyReading: Bool,
        readingProgress: Double?,
        isTrashed: Bool,
        coverAsset: Asset? = nil,
        coverAssets: [Asset] = [],
        coverStyle: BookCoverStyle,
        updatedAt: Date? = nil,
        lastOpenedAt: Date? = nil,
        trashedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.authors = authors
        self.summary = summary
        self.tags = tags
        self.dateAdded = dateAdded
        self.isFavorite = isFavorite
        self.isCurrentlyReading = isCurrentlyReading
        self.readingProgress = readingProgress
        self.isTrashed = isTrashed
        self.coverAssets = coverAssets.isEmpty ? coverAsset.map { [$0] } ?? [] : coverAssets
        self.coverStyle = coverStyle
        self.updatedAt = updatedAt ?? dateAdded
        self.lastOpenedAt = lastOpenedAt
        self.trashedAt = trashedAt
    }

    var authorLine: String {
        authors.joined(separator: ", ")
    }

    var coverAsset: Asset? {
        coverAssets.first(where: \.isCurrentCover) ?? coverAssets.first
    }

    var clampedReadingProgress: Double? {
        readingProgress.map { min(max($0, 0), 1) }
    }

    var metadataInput: BookMetadataInput {
        BookMetadataInput(
            title: title,
            subtitle: subtitle ?? "",
            authors: authors.isEmpty ? [""] : authors,
            tags: tags,
            summary: summary
        )
    }
}

nonisolated enum BookCoverStyle: String, CaseIterable, Sendable {
    case ember
    case forest
    case midnight
    case moss
    case ocean
    case plum
    case slate
    case sunset

    static func derived(from id: UUID) -> Self {
        let styles = allCases
        let byte = Int(id.uuid.0)
        return styles[byte % styles.count]
    }
}
