#if DEBUG
import SwiftUI

struct DebugLibraryCommands: Commands {
    let applicationModel: LibraryApplicationModel

    var body: some Commands {
        CommandMenu("Debug") {
            Button("Seed Sample Library") {
                Task {
                    await applicationModel.seedSampleLibrary()
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button("Reset Library") {
                Task {
                    await applicationModel.resetSampleLibrary()
                }
            }

            Divider()

            Button("Rebuild Search Index") {
                Task {
                    await applicationModel.rebuildSearchIndex()
                }
            }
        }
    }
}
#endif
