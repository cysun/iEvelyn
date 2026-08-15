import SwiftUI

struct LibraryBookDetailPlaceholder: View {
    let book: LibraryBook?

    var body: some View {
        if let book {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    BookCoverArtwork(book: book)
                        .frame(maxWidth: 190)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title)
                            .font(.title.bold())

                        if let subtitle = book.subtitle {
                            Text(subtitle)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }

                        Text(book.authorLine)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    if let progress = book.clampedReadingProgress {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Reading Progress")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ProgressView(value: progress)
                                .accessibilityLabel("Reading progress")
                                .accessibilityValue(
                                    Text(progress, format: .percent.precision(.fractionLength(0)))
                                )
                        }
                    }

                    Text(book.summary)
                        .font(.body)

                    Label(book.tags.joined(separator: "  •  "), systemImage: "tag")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Divider()

                    Label(
                        "Book editing and chapter management arrive in later steps.",
                        systemImage: "info.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: LibraryDesignTokens.detailMaximumWidth, alignment: .leading)
                .padding(LibraryDesignTokens.contentPadding)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .navigationTitle(book.title)
            .accessibilityIdentifier("library-detail")
        } else {
            ContentUnavailableView(
                "Select a Book",
                systemImage: "book.closed",
                description: Text("Choose a book from the grid or list to see its details.")
            )
            .accessibilityIdentifier("library-detail-empty")
        }
    }
}
