import SwiftUI

@main
struct iEvelynApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryRootView()
        }
        .defaultSize(width: 1120, height: 700)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutCommandButton()
            }

            LibraryCommands()
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
