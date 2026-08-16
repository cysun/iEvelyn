import SwiftUI

struct LibrarySearchResultsView: View {
    @Bindable var model: LibraryViewModel
    let onOpenResult: (LibrarySearchResult) -> Void

    var body: some View {
        if model.isSearching, model.visibleSearchResults.isEmpty {
            ContentUnavailableView {
                ProgressView()
                Text("Searching Library")
            } description: {
                Text("Searching canonical book metadata and Markdown…")
            }
            .accessibilityIdentifier("library-search-loading")
        } else if let searchErrorMessage = model.searchErrorMessage {
            ContentUnavailableView {
                Label("Search Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(searchErrorMessage)
            }
            .accessibilityIdentifier("library-search-error")
        } else if model.visibleSearchResults.isEmpty {
            ContentUnavailableView {
                Label("No Results", systemImage: "magnifyingglass")
            } description: {
                Text("No matching \(model.searchScope.title.lowercased()) were found in \(model.destination.title).")
            } actions: {
                Button("Clear Search") {
                    model.clearSearch()
                }
                .keyboardShortcut(.cancelAction)
            }
            .accessibilityIdentifier("library-search-empty")
        } else {
            List(model.visibleSearchResults) { result in
                Button {
                    onOpenResult(result)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: result.systemImage)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(result.bookTitle)
                                    .font(.headline)
                                    .lineLimit(1)
                                if let chapterTitle = result.chapterTitle {
                                    Text("— \(chapterTitle)")
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Text(highlightedSnippet(result.highlightedSnippet))
                                .font(.body)
                                .lineLimit(3)
                                .foregroundStyle(.primary)

                            if !result.authorLine.isEmpty {
                                Text(result.authorLine)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(result.accessibilityLabel)
                .accessibilityIdentifier("library-search-result-\(result.id)")
            }
            .accessibilityIdentifier("library-search-results")
        }
    }

    private func highlightedSnippet(_ value: String) -> AttributedString {
        var remaining = value[...]
        var result = AttributedString()
        while let start = remaining.range(of: LibrarySearchIndexer.highlightStart) {
            result.append(AttributedString(String(remaining[..<start.lowerBound])))
            remaining = remaining[start.upperBound...]
            guard let end = remaining.range(of: LibrarySearchIndexer.highlightEnd) else {
                var highlighted = AttributedString(String(remaining))
                highlighted.inlinePresentationIntent = .stronglyEmphasized
                result.append(highlighted)
                return result
            }
            var highlighted = AttributedString(String(remaining[..<end.lowerBound]))
            highlighted.inlinePresentationIntent = .stronglyEmphasized
            result.append(highlighted)
            remaining = remaining[end.upperBound...]
        }
        result.append(AttributedString(String(remaining)))
        return result
    }
}

private extension LibrarySearchResult {
    var systemImage: String {
        switch kind {
        case .metadata:
            "book.closed"
        case .chapterTitle:
            "list.bullet.rectangle"
        case .content:
            "text.page"
        }
    }

    var accessibilityLabel: String {
        var parts = [bookTitle]
        if !authorLine.isEmpty {
            parts.append("by \(authorLine)")
        }
        if let chapterTitle {
            parts.append(chapterTitle)
        }
        let snippet = highlightedSnippet
            .replacingOccurrences(of: LibrarySearchIndexer.highlightStart, with: "")
            .replacingOccurrences(of: LibrarySearchIndexer.highlightEnd, with: "")
        if snippet.localizedCaseInsensitiveCompare(bookTitle) != .orderedSame,
           snippet.localizedCaseInsensitiveCompare(chapterTitle ?? "") != .orderedSame {
            parts.append(snippet)
        }
        return parts.joined(separator: ", ")
    }
}
