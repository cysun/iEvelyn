import SwiftUI

private struct LibraryPresentationFocusedValueKey: FocusedValueKey {
    typealias Value = Binding<LibraryPresentation>
}

private struct LibraryDestinationFocusedValueKey: FocusedValueKey {
    typealias Value = Binding<LibraryDestination>
}

nonisolated enum LibraryInterchangeCommand: Equatable, Sendable {
    case createBackup
    case restoreBackup
    case importLegacyBundle
    case checkAndRepair
}

private struct LibraryInterchangeCommandFocusedValueKey: FocusedValueKey {
    typealias Value = Binding<LibraryInterchangeCommand?>
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

    var libraryInterchangeCommand: Binding<LibraryInterchangeCommand?>? {
        get { self[LibraryInterchangeCommandFocusedValueKey.self] }
        set { self[LibraryInterchangeCommandFocusedValueKey.self] = newValue }
    }
}

struct LibraryCommands: Commands {
    @FocusedBinding(\.libraryPresentation) private var presentation
    @FocusedBinding(\.libraryDestination) private var destination
    @FocusedBinding(\.libraryInterchangeCommand) private var interchangeCommand

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

            Divider()

            Button("Back Up Library…") {
                interchangeCommand = .createBackup
            }
            .disabled(interchangeCommand == nil)

            Button("Restore Library…") {
                interchangeCommand = .restoreBackup
            }
            .disabled(interchangeCommand == nil)

            Button("Import Legacy Library…") {
                interchangeCommand = .importLegacyBundle
            }
            .disabled(interchangeCommand == nil)

            Button("Check Library Integrity") {
                interchangeCommand = .checkAndRepair
            }
            .disabled(interchangeCommand == nil)
        }
    }
}
