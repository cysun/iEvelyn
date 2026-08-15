import SwiftUI

private struct LibraryPresentationFocusedValueKey: FocusedValueKey {
    typealias Value = Binding<LibraryPresentation>
}

private struct LibraryDestinationFocusedValueKey: FocusedValueKey {
    typealias Value = Binding<LibraryDestination>
}

extension FocusedValues {
    var libraryPresentation: Binding<LibraryPresentation>? {
        get { self[LibraryPresentationFocusedValueKey.self] }
        set { self[LibraryPresentationFocusedValueKey.self] = newValue }
    }

    var libraryDestination: Binding<LibraryDestination>? {
        get { self[LibraryDestinationFocusedValueKey.self] }
        set { self[LibraryDestinationFocusedValueKey.self] = newValue }
    }
}

struct LibraryCommands: Commands {
    @FocusedBinding(\.libraryPresentation) private var presentation
    @FocusedBinding(\.libraryDestination) private var destination

    var body: some Commands {
        CommandMenu("Library") {
            Button("Show All Books") {
                destination = .allBooks
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(destination == nil)

            Divider()

            Button("Show as Grid") {
                presentation = .grid
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(presentation == nil)

            Button("Show as List") {
                presentation = .list
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(presentation == nil)
        }
    }
}
