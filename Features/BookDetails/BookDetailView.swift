import SwiftUI

struct BookDetailView: View {
    let book: LibraryBook?
    let chapterModel: ChapterManagementViewModel
    let isBusy: Bool
    let loadCoverImage: (Asset) async throws -> Data
    let onCoverLoadError: (Error) -> Void
    let onEdit: (LibraryBook) -> Void
    let onToggleFavorite: (LibraryBook) -> Void
    let onMoveToTrash: (LibraryBook) -> Void
    let onRestore: (LibraryBook) -> Void
    let onDeletePermanently: (LibraryBook) -> Void
    let onChooseCover: (LibraryBook) -> Void
    let onRemoveCover: (LibraryBook) -> Void

    @State private var isConfirmingPermanentDeletion = false

    var body: some View {
        if let book {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    BookCoverArtwork(
                        book: book,
                        loadImageData: loadCoverImage,
                        onLoadError: onCoverLoadError
                    )
                        .frame(maxWidth: 190)
                        .frame(maxWidth: .infinity)

                    if !book.isTrashed {
                        coverActions(book)
                    }

                    titleSection(book)
                    actionSection(book)

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

                    ChapterManagementView(
                        model: chapterModel,
                        isReadOnly: book.isTrashed
                    )

                    GroupBox("About") {
                        Text(book.summary.isEmpty ? "No summary provided." : book.summary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(book.summary.isEmpty ? .secondary : .primary)
                            .padding(.vertical, 4)
                    }

                    metadataSection(book)

                    if !book.tags.isEmpty {
                        Label(book.tags.joined(separator: "  •  "), systemImage: "tag")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: LibraryDesignTokens.detailMaximumWidth, alignment: .leading)
                .padding(LibraryDesignTokens.contentPadding)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .accessibilityIdentifier("book-info-scroll")
            .navigationTitle(book.title)
            .confirmationDialog(
                "Delete “\(book.title)” permanently?",
                isPresented: $isConfirmingPermanentDeletion,
                titleVisibility: .visible
            ) {
                Button("Delete Permanently", role: .destructive) {
                    onDeletePermanently(book)
                }
                .accessibilityIdentifier("book-confirm-delete-permanently")
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This cannot be undone. All data owned by this book will be removed.")
            }
        } else {
            ContentUnavailableView(
                "Select a Book",
                systemImage: "book.closed",
                description: Text("Choose a book from the grid or list to see its details.")
            )
            .accessibilityIdentifier("library-detail-empty")
        }
    }

    private func coverActions(_ book: LibraryBook) -> some View {
        HStack {
            Spacer()

            Button(
                book.coverAsset == nil ? "Choose Cover…" : "Replace Cover…",
                systemImage: "photo.badge.plus"
            ) {
                onChooseCover(book)
            }
            .accessibilityIdentifier("book-choose-cover")

            if book.coverAsset != nil {
                Button("Remove Cover", systemImage: "photo.badge.minus", role: .destructive) {
                    onRemoveCover(book)
                }
                .accessibilityIdentifier("book-remove-cover")
            }

            Spacer()
        }
        .buttonStyle(.bordered)
        .disabled(isBusy)
    }

    private func titleSection(_ book: LibraryBook) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(book.title)
                    .font(.title.bold())

                if book.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel("Favorite")
                }
            }

            if let subtitle = book.subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Text(book.authorLine)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func actionSection(_ book: LibraryBook) -> some View {
        HStack {
            if book.isTrashed {
                Button("Restore", systemImage: "arrow.uturn.backward") {
                    onRestore(book)
                }
                .accessibilityIdentifier("book-restore")

                Button("Delete Permanently", systemImage: "trash", role: .destructive) {
                    isConfirmingPermanentDeletion = true
                }
                .accessibilityIdentifier("book-delete-permanently")
            } else {
                Button(book.isFavorite ? "Unfavorite" : "Favorite", systemImage: book.isFavorite ? "heart.slash" : "heart") {
                    onToggleFavorite(book)
                }
                .accessibilityIdentifier("book-toggle-favorite")

                Button("Edit", systemImage: "pencil") {
                    onEdit(book)
                }
                .accessibilityIdentifier("book-edit")

                Button("Move to Trash", systemImage: "trash", role: .destructive) {
                    onMoveToTrash(book)
                }
                .accessibilityIdentifier("book-move-to-trash")
            }
        }
        .buttonStyle(.bordered)
        .disabled(isBusy)
    }

    private func metadataSection(_ book: LibraryBook) -> some View {
        GroupBox("Library Details") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                metadataRow("Added", value: book.dateAdded.formatted(date: .abbreviated, time: .shortened))
                metadataRow("Updated", value: book.updatedAt.formatted(date: .abbreviated, time: .shortened))
                metadataRow(
                    "Last Opened",
                    value: book.lastOpenedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not opened"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}
