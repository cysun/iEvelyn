import SwiftUI

struct LibraryListView: View {
    let books: [LibraryBook]
    let onOpenBook: (LibraryBook) -> Void
    let onBookAction: (LibraryBook, BookManagementAction) -> Void
    let isSelecting: Bool
    let selectedBookIDs: Set<UUID>
    let onToggleSelection: (LibraryBook) -> Void

    var body: some View {
        VStack(spacing: 0) {
            listHeader
            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(books) { book in
                        HStack(spacing: 8) {
                            Button {
                                activate(book)
                            } label: {
                                HStack(spacing: 10) {
                                    if isSelecting {
                                        selectionIndicator(for: book)
                                    }
                                    listRow(for: book)
                                }
                                .contentShape(Rectangle())
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

                            if !isSelecting {
                                BookManagementMenu(book: book) { action in
                                    onBookAction(book, action)
                                }
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
            if isSelecting {
                Color.clear
                    .frame(width: 20, height: 1)
            }
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
        .font(.title3)
        .foregroundStyle(
            selectedBookIDs.contains(book.id) ? Color.accentColor : Color.secondary
        )
        .frame(width: 20)
        .accessibilityHidden(true)
    }

    private func selectionHint(for book: LibraryBook) -> String {
        guard isSelecting else { return "Open book" }
        return selectedBookIDs.contains(book.id) ? "Deselect book" : "Select book"
    }
}
