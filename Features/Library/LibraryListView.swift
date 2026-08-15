import SwiftUI

struct LibraryListView: View {
    let books: [LibraryBook]
    @Binding var selectedBookID: LibraryBook.ID?

    var body: some View {
        Table(books, selection: $selectedBookID) {
            TableColumn("Title") { book in
                HStack(spacing: 10) {
                    BookCoverArtwork(book: book, isSelected: selectedBookID == book.id)
                        .frame(width: 32, height: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        if let subtitle = book.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .width(min: 220, ideal: 320)

            TableColumn("Author") { book in
                Text(book.authorLine)
                    .lineLimit(1)
            }
            .width(min: 150, ideal: 190)

            TableColumn("Added") { book in
                Text(book.dateAdded, format: .dateTime.month(.abbreviated).day().year())
            }
            .width(min: 100, ideal: 120)

            TableColumn("Progress") { book in
                if let progress = book.clampedReadingProgress {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                } else {
                    Text("—")
                        .accessibilityLabel("Not started")
                }
            }
            .width(72)
        }
        .accessibilityIdentifier("library-list")
    }
}
