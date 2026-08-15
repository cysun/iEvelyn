import SwiftUI

enum BookManagementAction {
    case showInfo
    case edit
    case toggleFavorite
    case moveToTrash
    case restore
    case requestPermanentDeletion
}

struct BookManagementCommands: View {
    let book: LibraryBook
    let onAction: (BookManagementAction) -> Void

    var body: some View {
        Button("Book Info…", systemImage: "info.circle") {
            onAction(.showInfo)
        }

        if book.isTrashed {
            Divider()

            Button("Restore", systemImage: "arrow.uturn.backward") {
                onAction(.restore)
            }

            Button("Delete Permanently…", systemImage: "trash", role: .destructive) {
                onAction(.requestPermanentDeletion)
            }
        } else {
            Button("Edit Metadata…", systemImage: "pencil") {
                onAction(.edit)
            }

            Button(
                book.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: book.isFavorite ? "heart.slash" : "heart"
            ) {
                onAction(.toggleFavorite)
            }

            Divider()

            Button("Move to Trash", systemImage: "trash", role: .destructive) {
                onAction(.moveToTrash)
            }
        }
    }
}

struct BookManagementMenu: View {
    let book: LibraryBook
    let onAction: (BookManagementAction) -> Void

    var body: some View {
        Menu {
            BookManagementCommands(book: book, onAction: onAction)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Actions for \(book.title)")
        .accessibilityLabel("Actions for \(book.title)")
        .accessibilityIdentifier("book-actions-\(book.id.uuidString.lowercased())")
    }
}
