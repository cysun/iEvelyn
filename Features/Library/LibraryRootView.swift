import SwiftUI

struct LibraryRootView: View {
    @State private var model: LibraryViewModel

    init(model: LibraryViewModel = LibraryViewModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            LibrarySidebarView(selection: $model.destination)
        } content: {
            LibraryContentView(model: model)
        } detail: {
            LibraryBookDetailPlaceholder(book: model.selectedBook)
        }
        .searchable(
            text: $model.searchText,
            placement: .toolbar,
            prompt: "Search Library"
        )
        .focusedSceneValue(\.libraryPresentation, $model.presentation)
        .focusedSceneValue(\.libraryDestination, $model.destination)
        .accessibilityIdentifier("library-root")
    }
}

#Preview {
    LibraryRootView()
        .frame(width: 1120, height: 700)
}

#Preview("Empty library") {
    LibraryRootView(model: LibraryViewModel(books: []))
        .frame(width: 900, height: 600)
}
