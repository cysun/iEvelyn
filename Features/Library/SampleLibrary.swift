#if DEBUG
import Foundation

nonisolated struct SampleBookDefinition: Sendable {
    let title: String
    let subtitle: String?
    let authors: [String]
    let summary: String
    let tags: [String]
    let daysBeforeAdded: Int
    let isFavorite: Bool
    let readingProgress: Double?
}

/// Debug and preview data only. Release builds contain no sample-library provider.
nonisolated enum SampleLibrary {
    static let definitions: [SampleBookDefinition] = [
        SampleBookDefinition(
            title: "Kindred",
            subtitle: "A Novel",
            authors: ["Octavia E. Butler"],
            summary: "A modern writer is pulled through time and forced to confront the history that shaped her family.",
            tags: ["Fiction", "Time Travel"],
            daysBeforeAdded: 3,
            isFavorite: true,
            readingProgress: 0.42
        ),
        SampleBookDefinition(
            title: "The Left Hand of Darkness",
            subtitle: nil,
            authors: ["Ursula K. Le Guin"],
            summary: "An envoy crosses a frozen world while learning how culture, loyalty, and identity shape its people.",
            tags: ["Science Fiction", "Classic"],
            daysBeforeAdded: 46,
            isFavorite: true,
            readingProgress: nil
        ),
        SampleBookDefinition(
            title: "Piranesi",
            subtitle: nil,
            authors: ["Susanna Clarke"],
            summary: "A solitary explorer records the tides and statues of an impossible house whose secrets are beginning to surface.",
            tags: ["Fantasy", "Mystery"],
            daysBeforeAdded: 12,
            isFavorite: false,
            readingProgress: nil
        ),
        SampleBookDefinition(
            title: "The Dispossessed",
            subtitle: "An Ambiguous Utopia",
            authors: ["Ursula K. Le Guin"],
            summary: "A physicist travels between two worlds organized around opposing ideas of freedom, property, and responsibility.",
            tags: ["Science Fiction", "Politics"],
            daysBeforeAdded: 81,
            isFavorite: false,
            readingProgress: nil
        ),
        SampleBookDefinition(
            title: "Braiding Sweetgrass",
            subtitle: "Indigenous Wisdom, Scientific Knowledge and the Teachings of Plants",
            authors: ["Robin Wall Kimmerer"],
            summary: "Essays bring botany and Indigenous knowledge together through a practice of reciprocity with the living world.",
            tags: ["Nature", "Essays"],
            daysBeforeAdded: 37,
            isFavorite: true,
            readingProgress: nil
        ),
        SampleBookDefinition(
            title: "The City & the City",
            subtitle: nil,
            authors: ["China Miéville"],
            summary: "A murder investigation crosses the unseen border between two cities occupying the same physical space.",
            tags: ["Mystery", "Speculative Fiction"],
            daysBeforeAdded: 64,
            isFavorite: false,
            readingProgress: nil
        ),
        SampleBookDefinition(
            title: "A Psalm for the Wild-Built",
            subtitle: nil,
            authors: ["Becky Chambers"],
            summary: "A tea monk and a curious robot travel together, asking what people need in a world that has enough.",
            tags: ["Science Fiction", "Hopepunk"],
            daysBeforeAdded: 20,
            isFavorite: false,
            readingProgress: 0.18
        ),
        SampleBookDefinition(
            title: "Invisible Cities",
            subtitle: nil,
            authors: ["Italo Calvino"],
            summary: "A traveler describes a succession of imagined cities in a meditation on memory, desire, and urban life.",
            tags: ["Fiction", "Cities"],
            daysBeforeAdded: 112,
            isFavorite: false,
            readingProgress: nil
        )
    ]

    static func previewBooks(referenceDate: Date = .now) -> [LibraryBook] {
        definitions.map { definition in
            let id = UUID()
            return LibraryBook(
                id: id,
                title: definition.title,
                subtitle: definition.subtitle,
                authors: definition.authors,
                summary: definition.summary,
                tags: definition.tags,
                dateAdded: date(daysBefore: definition.daysBeforeAdded, referenceDate: referenceDate),
                isFavorite: definition.isFavorite,
                isCurrentlyReading: definition.readingProgress != nil,
                readingProgress: definition.readingProgress,
                isTrashed: false,
                coverStyle: .derived(from: id)
            )
        }
    }

    static func date(daysBefore: Int, referenceDate: Date) -> Date {
        Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: -daysBefore, to: referenceDate) ?? referenceDate
    }
}
#endif
