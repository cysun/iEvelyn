import Foundation

nonisolated struct LibraryQuery: Sendable {
    let destination: LibraryDestination
    let searchText: String
    let sortOrder: LibrarySortOrder
    let referenceDate: Date
    let calendar: Calendar

    init(
        destination: LibraryDestination,
        searchText: String,
        sortOrder: LibrarySortOrder,
        referenceDate: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.destination = destination
        self.searchText = searchText
        self.sortOrder = sortOrder
        self.referenceDate = referenceDate
        self.calendar = calendar
    }

    func apply(to books: [LibraryBook]) -> [LibraryBook] {
        books
            .filter(matchesDestination)
            .filter(matchesSearch)
            .sorted(by: areInIncreasingOrder)
    }

    private func matchesDestination(_ book: LibraryBook) -> Bool {
        switch destination {
        case .allBooks, .authors, .tags:
            return !book.isTrashed
        case .currentlyReading:
            return !book.isTrashed && book.isCurrentlyReading
        case .recentlyAdded:
            guard !book.isTrashed else { return false }
            let cutoff = calendar.date(byAdding: .day, value: -30, to: referenceDate) ?? referenceDate
            return book.dateAdded >= cutoff
        case .favorites:
            return !book.isTrashed && book.isFavorite
        case .trash:
            return book.isTrashed
        }
    }

    private func matchesSearch(_ book: LibraryBook) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let searchableValues = [
            book.title,
            book.subtitle,
            book.authorLine,
            book.summary
        ]
            .compactMap { $0 } + book.tags

        return searchableValues.contains {
            $0.localizedCaseInsensitiveContains(query)
        }
    }

    private func areInIncreasingOrder(_ lhs: LibraryBook, _ rhs: LibraryBook) -> Bool {
        let primaryComparison: ComparisonResult

        switch sortOrder {
        case .title:
            primaryComparison = lhs.title.localizedStandardCompare(rhs.title)
        case .author:
            primaryComparison = lhs.authorLine.localizedStandardCompare(rhs.authorLine)
        case .recentlyAdded:
            if lhs.dateAdded != rhs.dateAdded {
                return lhs.dateAdded > rhs.dateAdded
            }
            primaryComparison = lhs.title.localizedStandardCompare(rhs.title)
        case .recentlyOpened:
            switch (lhs.lastOpenedAt, rhs.lastOpenedAt) {
            case let (left?, right?) where left != right:
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                primaryComparison = lhs.title.localizedStandardCompare(rhs.title)
            }
        }

        if primaryComparison != .orderedSame {
            return primaryComparison == .orderedAscending
        }

        let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }

        return lhs.id < rhs.id
    }
}
