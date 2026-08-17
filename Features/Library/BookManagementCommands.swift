import SwiftUI

enum BookManagementAction {
    case edit
    case exportEPUB
    case exportMarkdown
    case toggleFavorite
    case clearReadingProgress
    case moveToTrash
    case restore
    case requestPermanentDeletion
}

struct BookManagementCommands: View {
    let book: LibraryBook
    let onAction: (BookManagementAction) -> Void

    var body: some View {
        if book.isTrashed {
            Button("Restore", systemImage: "arrow.uturn.backward") {
                onAction(.restore)
            }

            Button("Delete Permanently…", systemImage: "trash", role: .destructive) {
                onAction(.requestPermanentDeletion)
            }
        } else {
            Button("Edit Book…", systemImage: "pencil") {
                onAction(.edit)
            }

            Button("Export EPUB…", systemImage: "square.and.arrow.up") {
                onAction(.exportEPUB)
            }

            Button("Export Markdown…", systemImage: "doc.plaintext") {
                onAction(.exportMarkdown)
            }

            Divider()

            Button(
                book.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: book.isFavorite ? "heart.slash" : "heart"
            ) {
                onAction(.toggleFavorite)
            }

            if book.isCurrentlyReading {
                Button("Clear Reading Progress", systemImage: "arrow.counterclockwise") {
                    onAction(.clearReadingProgress)
                }
            }

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
