import SwiftUI

@main
struct iEvelynApp: App {
    @State private var applicationModel = LibraryApplicationModel()

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
    }
}

private enum SceneIdentifier {
    static let about = "about"
}

private struct AboutCommandButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About iEvelyn") {
            openWindow(id: SceneIdentifier.about)
        }
    }
}
