import SwiftUI

struct LibraryGridView: View {
    let books: [LibraryBook]
    @Binding var selectedBookID: LibraryBook.ID?

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
                    Button {
                        selectedBookID = book.id
                    } label: {
                        VStack(alignment: .leading, spacing: LibraryDesignTokens.cardSpacing) {
                            BookCoverArtwork(book: book, isSelected: selectedBookID == book.id)

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
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(book.title), by \(book.authorLine)")
                    .accessibilityValue(selectedBookID == book.id ? "Selected" : "")
                    .accessibilityIdentifier("book-\(book.id)")
                }
            }
            .padding(LibraryDesignTokens.contentPadding)
        }
        .accessibilityIdentifier("library-grid")
    }
}
