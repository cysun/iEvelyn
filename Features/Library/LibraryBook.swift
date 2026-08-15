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
    let coverStyle: BookCoverStyle

    var authorLine: String {
        authors.joined(separator: ", ")
    }

    var clampedReadingProgress: Double? {
        readingProgress.map { min(max($0, 0), 1) }
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
