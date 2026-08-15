import SwiftUI

struct LibraryGridView: View {
    let books: [LibraryBook]
    let loadCoverImage: (Asset) async throws -> Data
    let onCoverLoadError: (Error) -> Void
    let onOpenBook: (LibraryBook) -> Void
    let onBookAction: (LibraryBook, BookManagementAction) -> Void

    private let columns = [
        GridItem(
            .adaptive(
                minimum: LibraryDesignTokens.gridMinimumWidth,
                maximum: LibraryDesignTokens.gridMaximumWidth
            ),
            spacing: LibraryDesignTokens.gridSpacing,
            alignment: .top
        )
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: LibraryDesignTokens.gridSpacing) {
                ForEach(books) { book in
                    VStack(alignment: .leading, spacing: LibraryDesignTokens.cardSpacing) {
                        Button {
                            onOpenBook(book)
                        } label: {
                            BookCoverArtwork(
                                book: book,
                                loadImageData: loadCoverImage,
                                onLoadError: onCoverLoadError
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(book.title), by \(book.authorLine)")
                        .accessibilityHint("Open book")
                        .accessibilityIdentifier("book-\(book.id)")
                        .contextMenu {
                            BookManagementCommands(book: book) { action in
                                onBookAction(book, action)
                            }
                        }

                        HStack(alignment: .top, spacing: 6) {
                            Button {
                                onOpenBook(book)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(book.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)

                                    Text(book.authorLine)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHidden(true)

                            BookManagementMenu(book: book) { action in
                                onBookAction(book, action)
                            }
                        }
                    }
                }
            }
            .padding(LibraryDesignTokens.contentPadding)
        }
        .accessibilityIdentifier("library-grid")
    }
}
