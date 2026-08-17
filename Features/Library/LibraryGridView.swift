import SwiftUI

struct LibraryGridView: View {
    let books: [LibraryBook]
    let loadCoverImage: (Asset) async throws -> Data
    let onCoverLoadError: (Error) -> Void
    let onOpenBook: (LibraryBook) -> Void
    let onBookAction: (LibraryBook, BookManagementAction) -> Void
    let isSelecting: Bool
    let selectedBookIDs: Set<UUID>
    let onToggleSelection: (LibraryBook) -> Void

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
                            activate(book)
                        } label: {
                            BookCoverArtwork(
                                book: book,
                                loadImageData: loadCoverImage,
                                onLoadError: onCoverLoadError
                            )
                            .overlay {
                                if isSelecting && selectedBookIDs.contains(book.id) {
                                    RoundedRectangle(cornerRadius: LibraryDesignTokens.coverCornerRadius)
                                        .stroke(Color.accentColor, lineWidth: 4)
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                if isSelecting {
                                    selectionIndicator(for: book)
                                        .padding(8)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(book.title), by \(book.authorLine)")
                        .accessibilityHint(selectionHint(for: book))
                        .accessibilityValue(
                            isSelecting && selectedBookIDs.contains(book.id) ? "Selected" : ""
                        )
                        .accessibilityIdentifier("book-\(book.id)")
                        .contextMenu {
                            if !isSelecting {
                                BookManagementCommands(book: book) { action in
                                    onBookAction(book, action)
                                }
                            }
                        }

                        HStack(alignment: .top, spacing: 6) {
                            Button {
                                activate(book)
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

                            if !isSelecting {
                                BookManagementMenu(book: book) { action in
                                    onBookAction(book, action)
                                }
                            }
                        }
                    }
                }
            }
            .padding(LibraryDesignTokens.contentPadding)
        }
        .accessibilityIdentifier("library-grid")
    }

    private func activate(_ book: LibraryBook) {
        if isSelecting {
            onToggleSelection(book)
        } else {
            onOpenBook(book)
        }
    }

    private func selectionIndicator(for book: LibraryBook) -> some View {
        Image(
            systemName: selectedBookIDs.contains(book.id)
                ? "checkmark.circle.fill"
                : "circle"
        )
        .font(.title2)
        .foregroundStyle(
            selectedBookIDs.contains(book.id) ? Color.accentColor : Color.secondary,
            Color(nsColor: .windowBackgroundColor)
        )
        .accessibilityHidden(true)
    }

    private func selectionHint(for book: LibraryBook) -> String {
        guard isSelecting else { return "Open book" }
        return selectedBookIDs.contains(book.id) ? "Deselect book" : "Select book"
    }
}
