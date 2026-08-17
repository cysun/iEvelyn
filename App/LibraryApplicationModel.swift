import Observation
import SwiftUI
import UniformTypeIdentifiers

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
    private(set) var isPerformingInterchange = false
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

    func prepareLibraryBackup() async -> LibraryBackupPresentation? {
        guard !isPerformingInterchange,
              let repository = repository as? GRDBLibraryRepository else {
            return nil
        }
        isPerformingInterchange = true
        defer { isPerformingInterchange = false }

        do {
            let file = try await LibraryInterchangeService(repository: repository).createBackup()
            return LibraryBackupPresentation(file: file)
        } catch is CancellationError {
            return nil
        } catch {
            alert = LibraryApplicationAlert(
                title: "Could Not Back Up Library",
                message: error.localizedDescription
            )
            return nil
        }
    }

    func reportBackupWriteFailure(_ error: Error) {
        alert = LibraryApplicationAlert(
            title: "Could Not Save Library Backup",
            message: error.localizedDescription
        )
    }

    func checkAndRepairLibrary() async {
        guard !isPerformingInterchange,
              let repository = repository as? GRDBLibraryRepository else {
            return
        }
        isPerformingInterchange = true
        defer { isPerformingInterchange = false }

        do {
            let report = try await LibraryInterchangeService(repository: repository)
                .checkAndRepairIntegrity()
            alert = LibraryApplicationAlert(
                title: report.isHealthy ? "Library Is Healthy" : "Library Needs Attention",
                message: report.humanReadableText
            )
        } catch is CancellationError {
            return
        } catch {
            alert = LibraryApplicationAlert(
                title: "Could Not Check Library",
                message: error.localizedDescription
            )
        }
    }

    func restoreLibrary(from sourceURL: URL) async {
        guard !isPerformingInterchange else { return }

        let currentRepository = repository as? GRDBLibraryRepository
        let activeRootURL: URL
        if let currentRepository,
           let activeDatabaseURL = currentRepository.database.location.databaseURL,
           currentRepository.database.location.isProduction {
            activeRootURL = activeDatabaseURL.deletingLastPathComponent()
        } else if currentRepository == nil,
                  loadErrorMessage != nil,
                  launchConfiguration.mode == .production {
            do {
                activeRootURL = try LibraryDatabase.productionDatabaseURL()
                    .deletingLastPathComponent()
            } catch {
                alert = LibraryApplicationAlert(
                    title: "Restore Unavailable",
                    message: error.localizedDescription
                )
                return
            }
        } else {
            alert = LibraryApplicationAlert(
                title: "Restore Unavailable",
                message: LibraryInterchangeError.unavailableForCurrentLibrary.localizedDescription
            )
            return
        }
        isPerformingInterchange = true
        defer { isPerformingInterchange = false }

        let service = currentRepository.map { LibraryInterchangeService(repository: $0) }
            ?? LibraryInterchangeService(recoveryLibraryRootURL: activeRootURL)
        let originalLoadErrorMessage = loadErrorMessage
        var previousLibraryIsActive = true
        var preparedRestore: PreparedLibraryRestore?
        do {
            let prepared = try await service.prepareRestore(from: sourceURL)
            preparedRestore = prepared
            repository = nil
            isLoading = true
            loadErrorMessage = nil
            await Task.yield()

            if let currentRepository {
                try await currentRepository.database.close()
            }
            try await service.atomicallySwap(prepared, with: activeRootURL)
            previousLibraryIsActive = false

            do {
                let restoredRepository = try await Self.openProductionRepository()
                repository = restoredRepository
                isLoading = false
                loadErrorMessage = nil
                await service.discardPreparedRestore(prepared)
                preparedRestore = nil
                alert = LibraryApplicationAlert(
                    title: "Library Restored",
                    message: "Restored \(prepared.manifest.counts.books) book(s), \(prepared.manifest.counts.chapters) chapter(s), and \(prepared.manifest.counts.assets) asset(s) from a validated backup."
                )
            } catch let restoredLibraryError {
                do {
                    try await service.atomicallySwap(prepared, with: activeRootURL)
                    previousLibraryIsActive = true
                    await service.discardPreparedRestore(prepared)
                    preparedRestore = nil
                } catch {
                    loadErrorMessage = LibraryInterchangeError.atomicSwapFailed.localizedDescription
                    throw LibraryInterchangeError.atomicSwapFailed
                }
                do {
                    repository = try await Self.openProductionRepository()
                    loadErrorMessage = nil
                } catch {
                    repository = nil
                    loadErrorMessage = originalLoadErrorMessage ?? error.localizedDescription
                }
                isLoading = false
                throw restoredLibraryError
            }
        } catch is CancellationError {
            if previousLibraryIsActive, let preparedRestore {
                await service.discardPreparedRestore(preparedRestore)
            }
            if repository == nil {
                do {
                    repository = try await Self.openProductionRepository()
                    loadErrorMessage = nil
                } catch {
                    loadErrorMessage = originalLoadErrorMessage ?? error.localizedDescription
                }
                isLoading = false
            }
        } catch {
            if previousLibraryIsActive, let preparedRestore {
                await service.discardPreparedRestore(preparedRestore)
            }
            if repository == nil {
                do {
                    repository = try await Self.openProductionRepository()
                    loadErrorMessage = nil
                } catch {
                    loadErrorMessage = originalLoadErrorMessage ?? error.localizedDescription
                }
                isLoading = false
            }
            alert = LibraryApplicationAlert(
                title: "Could Not Restore Library",
                message: previousLibraryIsActive
                    ? "\(error.localizedDescription) The previous library remains in place."
                    : "\(error.localizedDescription) The previous library was preserved in the restore staging area and was not deleted."
            )
        }
    }

    func prepareLegacyImport(from sourceURL: URL) async -> LegacyImportPlan? {
        guard !isPerformingInterchange,
              let repository = repository as? GRDBLibraryRepository,
              repository.database.location.isProduction else {
            alert = LibraryApplicationAlert(
                title: "Legacy Import Unavailable",
                message: LegacyImportError.unavailableForCurrentLibrary.localizedDescription
            )
            return nil
        }
        isPerformingInterchange = true
        defer { isPerformingInterchange = false }

        do {
            return try await LegacyImportService(repository: repository)
                .prepareImport(from: sourceURL)
        } catch is CancellationError {
            return nil
        } catch {
            alert = LibraryApplicationAlert(
                title: "Could Not Validate Legacy Bundle",
                message: error.localizedDescription
            )
            return nil
        }
    }

    func importLegacyLibrary(
        _ plan: LegacyImportPlan,
        duplicateStrategy: LegacyDuplicateStrategy
    ) async -> Bool {
        guard !isPerformingInterchange,
              let currentRepository = repository as? GRDBLibraryRepository,
              let activeDatabaseURL = currentRepository.database.location.databaseURL,
              currentRepository.database.location.isProduction else {
            alert = LibraryApplicationAlert(
                title: "Legacy Import Unavailable",
                message: LegacyImportError.unavailableForCurrentLibrary.localizedDescription
            )
            return false
        }
        isPerformingInterchange = true
        defer { isPerformingInterchange = false }

        let service = LegacyImportService(repository: currentRepository)
        var previousLibraryIsActive = true
        var preparedImport: PreparedLegacyImport?
        do {
            let prepared = try await service.prepareStagedImport(
                plan,
                duplicateStrategy: duplicateStrategy
            )
            preparedImport = prepared
            let activeRootURL = activeDatabaseURL.deletingLastPathComponent()
            repository = nil
            isLoading = true
            loadErrorMessage = nil
            await Task.yield()

            try await currentRepository.database.close()
            try await service.atomicallySwap(prepared, with: activeRootURL)
            previousLibraryIsActive = false

            do {
                repository = try await Self.openProductionRepository()
                isLoading = false
                await service.discardPreparedImport(prepared)
                preparedImport = nil
                alert = LibraryApplicationAlert(
                    title: "Legacy Import Complete",
                    message: "Imported \(prepared.importedBookCount) book(s), \(prepared.importedChapterCount) chapter(s), and \(prepared.importedAssetCount) asset record(s). Skipped \(prepared.skippedDuplicateCount) likely duplicate book(s). The permanent reconciliation report is in \(prepared.reconciliationReportRelativePath)."
                )
                return true
            } catch let importedLibraryError {
                do {
                    try await service.atomicallySwap(prepared, with: activeRootURL)
                    previousLibraryIsActive = true
                    await service.discardPreparedImport(prepared)
                    preparedImport = nil
                    repository = try await Self.openProductionRepository()
                    isLoading = false
                } catch {
                    loadErrorMessage = LegacyImportError.atomicSwapFailed.localizedDescription
                    throw LegacyImportError.atomicSwapFailed
                }
                throw importedLibraryError
            }
        } catch is CancellationError {
            if previousLibraryIsActive, let preparedImport {
                await service.discardPreparedImport(preparedImport)
            }
            if repository == nil {
                repository = try? await Self.openProductionRepository()
                isLoading = false
            }
            return false
        } catch {
            if previousLibraryIsActive, let preparedImport {
                await service.discardPreparedImport(preparedImport)
            }
            if repository == nil {
                repository = try? await Self.openProductionRepository()
                isLoading = false
            }
            alert = LibraryApplicationAlert(
                title: "Could Not Import Legacy Library",
                message: previousLibraryIsActive
                    ? "\(error.localizedDescription) The previous library remains active."
                    : "\(error.localizedDescription) The previous library was preserved in the import staging area and was not deleted."
            )
            return false
        }
    }

    private static func openProductionRepository() async throws -> GRDBLibraryRepository {
        let repository = GRDBLibraryRepository(database: try await LibraryDatabase.openProduction())
        try await repository.prepareAssetStorage()
        _ = try await repository.repairAssetStorage()
        return repository
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
    @State private var interchangeCommand: LibraryInterchangeCommand?
    @State private var backupPresentation: LibraryBackupPresentation?
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var isConfirmingRestore = false
    @State private var isSelectingLegacyBundle = false
    @State private var legacyImportPlan: LegacyImportPlan?

    var body: some View {
        Group {
            if let repository = applicationModel.repository {
                LibraryRootView(repository: repository)
            } else if applicationModel.isLoading || applicationModel.isPerformingInterchange {
                ContentUnavailableView {
                    ProgressView()
                    Text(
                        applicationModel.isPerformingInterchange
                            ? "Restoring Library"
                            : "Opening Library"
                    )
                } description: {
                    Text(
                        applicationModel.isPerformingInterchange
                            ? "Validating the selected backup before replacing the local library…"
                            : "Preparing the local iEvelyn database…"
                    )
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
                    .accessibilityIdentifier("library-load-retry")

                    Button("Restore from Backup…") {
                        isConfirmingRestore = true
                    }
                    .accessibilityIdentifier("library-load-restore")
                }
                .accessibilityIdentifier("library-load-error")
            }
        }
        .task {
            await applicationModel.loadLibraryIfNeeded()
        }
        .focusedSceneValue(\.libraryInterchangeCommand, $interchangeCommand)
        .onChange(of: interchangeCommand) { _, command in
            guard let command else { return }
            interchangeCommand = nil
            switch command {
            case .createBackup:
                Task {
                    guard let presentation = await applicationModel.prepareLibraryBackup() else {
                        return
                    }
                    backupPresentation = presentation
                    isExportingBackup = true
                }
            case .restoreBackup:
                isConfirmingRestore = true
            case .importLegacyBundle:
                isSelectingLegacyBundle = true
            case .checkAndRepair:
                Task {
                    await applicationModel.checkAndRepairLibrary()
                }
            }
        }
        .background {
            LibraryBackupFileExporter(
                isPresented: $isExportingBackup,
                presentation: backupPresentation
            ) { result in
                isExportingBackup = false
                backupPresentation = nil
                if case .failure(let error) = result,
                   (error as? CocoaError)?.code != .userCancelled {
                    applicationModel.reportBackupWriteFailure(error)
                }
            }
        }
        .fileImporter(
            isPresented: $isImportingBackup,
            allowedContentTypes: [LibraryBackupDocument.contentType, .zip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let sourceURL = urls.first else { return }
                Task {
                    await applicationModel.restoreLibrary(from: sourceURL)
                }
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled {
                    applicationModel.alert = LibraryApplicationAlert(
                        title: "Could Not Open Library Backup",
                        message: error.localizedDescription
                    )
                }
            }
        }
        .fileImporter(
            isPresented: $isSelectingLegacyBundle,
            allowedContentTypes: [LegacyMigrationBundleType.contentType, .zip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let sourceURL = urls.first else { return }
                Task {
                    legacyImportPlan = await applicationModel.prepareLegacyImport(from: sourceURL)
                }
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled {
                    applicationModel.alert = LibraryApplicationAlert(
                        title: "Could Not Open Legacy Bundle",
                        message: error.localizedDescription
                    )
                }
            }
        }
        .sheet(item: $legacyImportPlan) { plan in
            LegacyImportReviewView(plan: plan) { strategy in
                await applicationModel.importLegacyLibrary(
                    plan,
                    duplicateStrategy: strategy
                )
            }
        }
        .confirmationDialog(
            "Restore Library?",
            isPresented: $isConfirmingRestore,
            titleVisibility: .visible
        ) {
            Button("Choose Backup and Restore…", role: .destructive) {
                isImportingBackup = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The selected backup will replace the current library only after every database, asset, count, and checksum check passes.")
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

private struct LibraryBackupFileExporter: View {
    @Binding var isPresented: Bool
    let presentation: LibraryBackupPresentation?
    let onCompletion: (Result<URL, Error>) -> Void

    var body: some View {
        Color.clear
            .fileExporter(
                isPresented: $isPresented,
                document: presentation.map { LibraryBackupDocument(data: $0.file.data) },
                contentType: LibraryBackupDocument.contentType,
                defaultFilename: presentation?.file.suggestedFilename
                    ?? "iEvelyn Library",
                onCompletion: onCompletion
            )
    }
}
