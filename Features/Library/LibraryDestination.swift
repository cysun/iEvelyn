import Foundation

nonisolated enum LibraryDestination: String, CaseIterable, Identifiable, Sendable {
    case allBooks
    case currentlyReading
    case recentlyAdded
    case favorites
    case authors
    case tags
    case trash

    var id: Self { self }

    var title: String {
        switch self {
        case .allBooks:
            "All Books"
        case .currentlyReading:
            "Currently Reading"
        case .recentlyAdded:
            "Recently Added"
        case .favorites:
            "Favorites"
        case .authors:
            "Authors"
        case .tags:
            "Tags"
        case .trash:
            "Trash"
        }
    }

    var systemImage: String {
        switch self {
        case .allBooks:
            "books.vertical"
        case .currentlyReading:
            "book.pages"
        case .recentlyAdded:
            "clock"
        case .favorites:
            "heart"
        case .authors:
            "person.2"
        case .tags:
            "tag"
        case .trash:
            "trash"
        }
    }

    var accessibilityIdentifier: String {
        "sidebar-\(rawValue)"
    }
}

nonisolated enum LibraryPresentation: String, CaseIterable, Identifiable, Sendable {
    case grid
    case list

    var id: Self { self }

    var title: String {
        switch self {
        case .grid:
            "Grid View"
        case .list:
            "List View"
        }
    }

    var systemImage: String {
        switch self {
        case .grid:
            "square.grid.2x2"
        case .list:
            "list.bullet"
        }
    }
}

nonisolated enum LibrarySortOrder: String, CaseIterable, Identifiable, Sendable {
    case title
    case author
    case recentlyAdded

    var id: Self { self }

    var title: String {
        switch self {
        case .title:
            "Title"
        case .author:
            "Author"
        case .recentlyAdded:
            "Recently Added"
        }
    }
}
