import SwiftUI

struct LibrarySidebarView: View {
    @Binding var selection: LibraryDestination

    private var optionalSelection: Binding<LibraryDestination?> {
        Binding(
            get: { selection },
            set: { newValue in
                if let newValue {
                    selection = newValue
                }
            }
        )
    }

    var body: some View {
        List(selection: optionalSelection) {
            Section("Library") {
                destinationRow(.allBooks)
                destinationRow(.currentlyReading)
                destinationRow(.recentlyAdded)
                destinationRow(.favorites)
            }

            Section("Browse") {
                destinationRow(.authors)
                destinationRow(.tags)
            }

            Section {
                destinationRow(.trash)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Library")
        .navigationSplitViewColumnWidth(
            min: LibraryDesignTokens.sidebarMinimumWidth,
            ideal: LibraryDesignTokens.sidebarIdealWidth
        )
        .accessibilityIdentifier("library-sidebar")
    }

    private func destinationRow(_ destination: LibraryDestination) -> some View {
        Label(destination.title, systemImage: destination.systemImage)
            .tag(destination)
            .accessibilityIdentifier(destination.accessibilityIdentifier)
    }
}
