import SwiftUI

@main
struct iEvelynApp: App {
    @State private var applicationModel = LibraryApplicationModel()
    @State private var readerSettings = ReaderSettingsStore()

    var body: some Scene {
        WindowGroup {
            LibraryApplicationRootView(applicationModel: applicationModel)
        }
        .defaultSize(width: 1120, height: 700)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutCommandButton()
            }

            LibraryCommands()

#if DEBUG
            DebugLibraryCommands(applicationModel: applicationModel)
#endif
        }

        Window("About iEvelyn", id: SceneIdentifier.about) {
            AboutView()
        }
        .windowResizability(.contentSize)

        WindowGroup("Reader", id: SceneIdentifier.reader, for: ReaderWindowRoute.self) { route in
            ReaderApplicationRootView(
                applicationModel: applicationModel,
                route: route.wrappedValue,
                settings: readerSettings
            )
        }
        .defaultSize(width: 1_080, height: 760)
    }
}

enum SceneIdentifier {
    static let about = "about"
    static let reader = "reader"
}

private struct AboutCommandButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About iEvelyn") {
            openWindow(id: SceneIdentifier.about)
        }
    }
}
