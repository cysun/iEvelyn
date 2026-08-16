import Observation
import SwiftUI

nonisolated enum LibraryLaunchMode: Equatable, Sendable {
    case production
    case testingInMemory(seedSampleLibrary: Bool)
}

nonisolated struct LibraryLaunchConfiguration: Equatable, Sendable {
    static let uiTestingArgument = "--ui-testing"
    static let seedSampleLibraryArgument = "--seed-sample-library"

    let mode: LibraryLaunchMode

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
#if DEBUG
        if arguments.contains(Self.uiTestingArgument) {
            mode = .testingInMemory(
                seedSampleLibrary: arguments.contains(Self.seedSampleLibraryArgument)
            )
            return
        }
#endif
        mode = .production
    }
}

@MainActor
@Observable
final class LibraryApplicationModel {
    private(set) var repository: (any LibraryRepository)?
    private(set) var isLoading = true
    private(set) var loadErrorMessage: String?
    var alert: LibraryApplicationAlert?

    private let launchConfiguration: LibraryLaunchConfiguration
    private var didBeginLoading = false

    init(launchConfiguration: LibraryLaunchConfiguration = LibraryLaunchConfiguration()) {
        self.launchConfiguration = launchConfiguration
    }

    func loadLibraryIfNeeded() async {
        guard !didBeginLoading else { return }
        didBeginLoading = true
        isLoading = true
        loadErrorMessage = nil

        do {
            let database: LibraryDatabase
            switch launchConfiguration.mode {
            case .production:
                database = try await LibraryDatabase.openProduction()
            case .testingInMemory:
                database = try LibraryDatabase.makeInMemory()
            }

            let repository = GRDBLibraryRepository(database: database)
#if DEBUG
            if case .testingInMemory(let shouldSeed) = launchConfiguration.mode, shouldSeed {
                try await repository.seedSampleLibrary()
            }
#endif
            try await repository.prepareAssetStorage()
            let assetRepairReport = try await repository.repairAssetStorage()
            self.repository = repository
            isLoading = false

            if assetRepairReport.failedRemovalCount > 0 {
                alert = LibraryApplicationAlert(
                    title: "Asset Cleanup Needed",
                    message: "\(assetRepairReport.failedRemovalCount) obsolete asset file(s) could not be removed. iEvelyn will retry the cleanup the next time the library opens."
                )
            } else if !assetRepairReport.missingReferencedRelativePaths.isEmpty {
                alert = LibraryApplicationAlert(
                    title: "Some Asset Files Are Missing",
                    message: "\(assetRepairReport.missingReferencedRelativePaths.count) library asset file(s) are missing. Affected covers will use generated artwork until they are replaced or removed."
                )
            }
        } catch {
            isLoading = false
            loadErrorMessage = error.localizedDescription
        }
    }

    func retryLoading() async {
        repository = nil
        didBeginLoading = false
        await loadLibraryIfNeeded()
    }

#if DEBUG
    func seedSampleLibrary() async {
        guard let repository = repository as? GRDBLibraryRepository else {
            alert = LibraryApplicationAlert(
                title: "Sample Library Unavailable",
                message: "The library database has not finished loading."
            )
            return
        }

        do {
            let inserted = try await repository.seedSampleLibrary()
            alert = LibraryApplicationAlert(
                title: inserted ? "Sample Library Added" : "Library Not Empty",
                message: inserted
                    ? "Eight sample books were added to this Debug library."
                    : "Reset the Debug library before seeding sample books again."
            )
        } catch {
            alert = LibraryApplicationAlert(
                title: "Could Not Seed Library",
                message: error.localizedDescription
            )
        }
    }

    func resetSampleLibrary() async {
        guard let repository = repository as? GRDBLibraryRepository else {
            alert = LibraryApplicationAlert(
                title: "Reset Unavailable",
                message: "The library database has not finished loading."
            )
            return
        }

        do {
            try await repository.resetSampleLibrary()
            alert = LibraryApplicationAlert(
                title: "Library Reset",
                message: "All Debug library records were removed."
            )
        } catch {
            alert = LibraryApplicationAlert(
                title: "Could Not Reset Library",
                message: error.localizedDescription
            )
        }
    }

    func rebuildSearchIndex() async {
        guard let repository else {
            alert = LibraryApplicationAlert(
                title: "Search Repair Unavailable",
                message: "The library database has not finished loading."
            )
            return
        }

        do {
            let report = try await repository.rebuildSearchIndex()
            alert = LibraryApplicationAlert(
                title: "Search Index Rebuilt",
                message: "Indexed \(report.rebuiltDocumentCount) search documents across \(report.indexedBookCount) books."
            )
        } catch {
            alert = LibraryApplicationAlert(
                title: "Could Not Rebuild Search Index",
                message: error.localizedDescription
            )
        }
    }
#endif
}

nonisolated struct LibraryApplicationAlert: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let message: String
}

struct LibraryApplicationRootView: View {
    @Bindable var applicationModel: LibraryApplicationModel

    var body: some View {
        Group {
            if let repository = applicationModel.repository {
                LibraryRootView(repository: repository)
            } else if applicationModel.isLoading {
                ContentUnavailableView {
                    ProgressView()
                    Text("Opening Library")
                } description: {
                    Text("Preparing the local iEvelyn database…")
                }
                .accessibilityIdentifier("library-loading")
            } else {
                ContentUnavailableView {
                    Label("Library Unavailable", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(applicationModel.loadErrorMessage ?? "The local library could not be opened.")
                } actions: {
                    Button("Try Again") {
                        Task {
                            await applicationModel.retryLoading()
                        }
                    }
                }
                .accessibilityIdentifier("library-load-error")
            }
        }
        .task {
            await applicationModel.loadLibraryIfNeeded()
        }
        .alert(item: $applicationModel.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
