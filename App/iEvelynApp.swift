import SwiftUI

@main
struct iEvelynApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryRootView()
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutCommandButton()
            }
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
