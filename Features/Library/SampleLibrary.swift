import Foundation

/// The only source of Step 2 sample books. Persistence replaces this provider in Step 3.
nonisolated enum SampleLibrary {
    static func books(
        referenceDate: Date = .now,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [LibraryBook] {
        [
            LibraryBook(
                id: "kindred",
                title: "Kindred",
                subtitle: "A Novel",
                authors: ["Octavia E. Butler"],
                summary: "A modern writer is pulled through time and forced to confront the history that shaped her family.",
                tags: ["Fiction", "Time Travel"],
                dateAdded: date(daysBefore: 3, referenceDate: referenceDate, calendar: calendar),
                isFavorite: true,
                isCurrentlyReading: true,
                readingProgress: 0.42,
                isTrashed: false,
                coverStyle: .ember
            ),
            LibraryBook(
                id: "left-hand-of-darkness",
                title: "The Left Hand of Darkness",
                subtitle: nil,
                authors: ["Ursula K. Le Guin"],
                summary: "An envoy crosses a frozen world while learning how culture, loyalty, and identity shape its people.",
                tags: ["Science Fiction", "Classic"],
                dateAdded: date(daysBefore: 46, referenceDate: referenceDate, calendar: calendar),
                isFavorite: true,
                isCurrentlyReading: false,
                readingProgress: nil,
                isTrashed: false,
                coverStyle: .midnight
            ),
            LibraryBook(
                id: "piranesi",
                title: "Piranesi",
                subtitle: nil,
                authors: ["Susanna Clarke"],
                summary: "A solitary explorer records the tides and statues of an impossible house whose secrets are beginning to surface.",
                tags: ["Fantasy", "Mystery"],
                dateAdded: date(daysBefore: 12, referenceDate: referenceDate, calendar: calendar),
                isFavorite: false,
                isCurrentlyReading: false,
                readingProgress: nil,
                isTrashed: false,
                coverStyle: .ocean
            ),
            LibraryBook(
                id: "dispossessed",
                title: "The Dispossessed",
                subtitle: "An Ambiguous Utopia",
                authors: ["Ursula K. Le Guin"],
                summary: "A physicist travels between two worlds organized around opposing ideas of freedom, property, and responsibility.",
                tags: ["Science Fiction", "Politics"],
                dateAdded: date(daysBefore: 81, referenceDate: referenceDate, calendar: calendar),
                isFavorite: false,
                isCurrentlyReading: false,
                readingProgress: nil,
                isTrashed: false,
                coverStyle: .slate
            ),
            LibraryBook(
                id: "braiding-sweetgrass",
                title: "Braiding Sweetgrass",
                subtitle: "Indigenous Wisdom, Scientific Knowledge and the Teachings of Plants",
                authors: ["Robin Wall Kimmerer"],
                summary: "Essays bring botany and Indigenous knowledge together through a practice of reciprocity with the living world.",
                tags: ["Nature", "Essays"],
                dateAdded: date(daysBefore: 37, referenceDate: referenceDate, calendar: calendar),
                isFavorite: true,
                isCurrentlyReading: false,
                readingProgress: nil,
                isTrashed: false,
                coverStyle: .forest
            ),
            LibraryBook(
                id: "city-and-the-city",
                title: "The City & the City",
                subtitle: nil,
                authors: ["China Miéville"],
                summary: "A murder investigation crosses the unseen border between two cities occupying the same physical space.",
                tags: ["Mystery", "Speculative Fiction"],
                dateAdded: date(daysBefore: 64, referenceDate: referenceDate, calendar: calendar),
                isFavorite: false,
                isCurrentlyReading: false,
                readingProgress: nil,
                isTrashed: false,
                coverStyle: .plum
            ),
            LibraryBook(
                id: "psalm-for-the-wild-built",
                title: "A Psalm for the Wild-Built",
                subtitle: nil,
                authors: ["Becky Chambers"],
                summary: "A tea monk and a curious robot travel together, asking what people need in a world that has enough.",
                tags: ["Science Fiction", "Hopepunk"],
                dateAdded: date(daysBefore: 20, referenceDate: referenceDate, calendar: calendar),
                isFavorite: false,
                isCurrentlyReading: true,
                readingProgress: 0.18,
                isTrashed: false,
                coverStyle: .sunset
            ),
            LibraryBook(
                id: "invisible-cities",
                title: "Invisible Cities",
                subtitle: nil,
                authors: ["Italo Calvino"],
                summary: "A traveler describes a succession of imagined cities in a meditation on memory, desire, and urban life.",
                tags: ["Fiction", "Cities"],
                dateAdded: date(daysBefore: 112, referenceDate: referenceDate, calendar: calendar),
                isFavorite: false,
                isCurrentlyReading: false,
                readingProgress: nil,
                isTrashed: false,
                coverStyle: .moss
            )
        ]
    }

    private static func date(
        daysBefore: Int,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date {
        calendar.date(byAdding: .day, value: -daysBefore, to: referenceDate) ?? referenceDate
    }
}
