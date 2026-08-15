import SwiftUI

struct LibraryListView: View {
    let books: [LibraryBook]
    let onOpenBook: (LibraryBook) -> Void
    let onBookAction: (LibraryBook, BookManagementAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            listHeader
            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(books) { book in
                        HStack(spacing: 8) {
                            Button {
                                onOpenBook(book)
                            } label: {
                                listRow(for: book)
                                    .contentShape(Rectangle())
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

                            BookManagementMenu(book: book) { action in
                                onBookAction(book, action)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 2)

                        Divider()
                            .padding(.leading, 14)
                    }
                }
            }
            .accessibilityIdentifier("library-list")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var listHeader: some View {
        HStack(spacing: 8) {
            Text("Title")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Author")
                .frame(width: 190, alignment: .leading)
            Text("Added")
                .frame(width: 120, alignment: .leading)
            Text("Progress")
                .frame(width: 72, alignment: .leading)
            Color.clear
                .frame(width: 24, height: 1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .padding(.vertical, 7)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityHidden(true)
    }

    private func listRow(for book: LibraryBook) -> some View {
        HStack(spacing: 10) {
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
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(book.authorLine)
                .lineLimit(1)
                .frame(width: 190, alignment: .leading)

            Text(book.dateAdded, format: .dateTime.month(.abbreviated).day().year())
                .frame(width: 120, alignment: .leading)

            Group {
                if let progress = book.clampedReadingProgress {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                } else {
                    Text("—")
                        .accessibilityLabel("Not started")
                }
            }
            .frame(width: 72, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}
