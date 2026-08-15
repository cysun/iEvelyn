import SwiftUI

struct LibraryContentView: View {
    @Bindable var model: LibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.visibleBooks.isEmpty {
                emptyState
            } else {
                switch model.presentation {
                case .grid:
                    LibraryGridView(
                        books: model.visibleBooks,
                        selectedBookID: $model.selectedBookID
                    )
                case .list:
                    LibraryListView(
                        books: model.visibleBooks,
                        selectedBookID: $model.selectedBookID
                    )
                }
            }
        }
        .navigationTitle(model.destination.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                sortMenu
                presentationPicker
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.destination.title)
                .font(.title2.bold())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.destination.title)
                .accessibilityIdentifier("library-content-title")

            Spacer()

            Text(bookCountDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .accessibilityIdentifier("library-book-count")
        }
        .padding(.horizontal, LibraryDesignTokens.contentPadding)
        .padding(.vertical, 16)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyStateTitle, systemImage: emptyStateSystemImage)
        } description: {
            Text(emptyStateDescription)
        } actions: {
            if hasSearchText {
                Button("Clear Search") {
                    model.clearSearch()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("library-empty-state")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $model.sortOrder) {
                ForEach(LibrarySortOrder.allCases) { sortOrder in
                    Text(sortOrder.title)
                        .tag(sortOrder)
                }
            }
        } label: {
            Label("Sort: \(model.sortOrder.title)", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort books")
        .accessibilityIdentifier("library-sort-menu")
    }

    private var presentationPicker: some View {
        Picker("Presentation", selection: $model.presentation) {
            ForEach(LibraryPresentation.allCases) { presentation in
                Image(systemName: presentation.systemImage)
                    .accessibilityLabel(presentation.title)
                    .accessibilityIdentifier("library-view-\(presentation.rawValue)")
                    .tag(presentation)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Switch between grid and list views")
    }

    private var bookCountDescription: String {
        let count = model.visibleBooks.count
        return count == 1 ? "1 Book" : "\(count) Books"
    }

    private var hasSearchText: Bool {
        !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyStateTitle: String {
        if hasSearchText {
            return "No Results"
        }

        if model.destination == .trash {
            return "Trash is Empty"
        }

        return "No Books Here"
    }

    private var emptyStateSystemImage: String {
        if hasSearchText {
            return "magnifyingglass"
        }

        return model.destination == .trash ? "trash" : "books.vertical"
    }

    private var emptyStateDescription: String {
        if hasSearchText {
            return "No books in \(model.destination.title) match “\(model.searchText)”."
        }

        if model.destination == .trash {
            return "Books you remove will remain here until they are permanently deleted."
        }

        return "This collection does not contain any books yet."
    }
}
