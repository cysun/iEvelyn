import CryptoKit
import Darwin
import Foundation
import GRDB
import ImageIO
import UniformTypeIdentifiers
import ZIPFoundation

nonisolated enum LegacyMigrationBundleType {
    static let formatIdentifier = "org.cysun.iEvelyn.legacy-export"
    static let typeIdentifier = "org.cysun.ievelyn.legacy-export"
    static let currentFormatVersion = 1
    static let filenameExtension = "ievelynlegacy"
    static let contentType = UTType(
        importedAs: typeIdentifier,
        conformingTo: .zip
    )
}

nonisolated enum LegacyDuplicateStrategy: String, Codable, CaseIterable, Sendable {
    case skipLikelyDuplicates
    case importAsNew

    var title: String {
        switch self {
        case .skipLikelyDuplicates:
            "Skip likely duplicates"
        case .importAsNew:
            "Import another copy"
        }
    }

    var explanation: String {
        switch self {
        case .skipLikelyDuplicates:
            "Books with the same normalized title and author remain unchanged."
        case .importAsNew:
            "Every legacy book receives new UUIDs, including likely duplicates."
        }
    }
}

nonisolated struct LegacyDuplicateConflict: Identifiable, Equatable, Sendable {
    var id: Int { legacyBookID }

    let legacyBookID: Int
    let title: String
    let author: String
    let existingBookIDs: [UUID]
}

nonisolated struct LegacyImportDryRunSummary: Equatable, Sendable {
    let sourceSnapshotTimestamp: String
    let books: Int
    let chapters: Int
    let assets: Int
    let assetBytes: Int64
    let exporterWarnings: Int
    let exporterSkippedItems: Int
    let exporterSkippedCount: Int
    let importerWarnings: [String]
    let duplicateConflicts: [LegacyDuplicateConflict]
}

nonisolated struct LegacyImportPlan: Identifiable, Sendable {
    let id = UUID()
    let archiveData: Data
    let archiveChecksum: String
    let bundle: ValidatedLegacyBundle
    let summary: LegacyImportDryRunSummary
}

nonisolated struct PreparedLegacyImport: Equatable, Sendable {
    let stagedLibraryRootURL: URL
    let importedBookCount: Int
    let importedChapterCount: Int
    let importedAssetCount: Int
    let skippedDuplicateCount: Int
    let reconciliationReportRelativePath: String
}

nonisolated enum LegacyImportError: LocalizedError, Equatable, Sendable {
    case unavailableForCurrentLibrary
    case invalidArchive
    case missingManifest
    case invalidManifest
    case unsupportedFormatVersion(Int)
    case unsafeOrUnexpectedEntry(String)
    case missingEntry(String)
    case fileSizeMismatch(String)
    case checksumMismatch(String)
    case invalidUTF8(String)
    case invalidJSON(String)
    case countMismatch
    case invalidReference(String)
    case unsupportedMedia(Int)
    case libraryChangedSinceDryRun
    case sourceLibraryInvalid
    case stagingFailed
    case atomicSwapFailed

    var errorDescription: String? {
        switch self {
        case .unavailableForCurrentLibrary:
            "Legacy import requires the on-disk production library."
        case .invalidArchive:
            "The selected file is not a valid iEvelyn legacy migration bundle."
        case .missingManifest:
            "The legacy bundle does not contain manifest.json."
        case .invalidManifest:
            "The legacy bundle manifest is invalid or internally inconsistent."
        case .unsupportedFormatVersion(let version):
            "This legacy bundle uses unsupported format version \(version). Update iEvelyn before importing it."
        case .unsafeOrUnexpectedEntry:
            "The legacy bundle contains an unsafe or unexpected file and was rejected."
        case .missingEntry(let path):
            "The legacy bundle is missing the required file \(path)."
        case .fileSizeMismatch(let path):
            "The file \(path) does not match the byte count in the legacy manifest."
        case .checksumMismatch(let path):
            "The file \(path) does not match the checksum in the legacy manifest."
        case .invalidUTF8(let path):
            "The text file \(path) is not valid UTF-8."
        case .invalidJSON(let path):
            "The JSON file \(path) does not match the legacy bundle contract."
        case .countMismatch:
            "The legacy bundle counts do not match its records and reports."
        case .invalidReference(let description):
            "The legacy bundle contains an inconsistent reference: \(description)"
        case .unsupportedMedia(let legacyID):
            "Legacy asset \(legacyID) is not a complete JPEG, PNG, GIF, HEIC, or HEIF image. It was not imported."
        case .libraryChangedSinceDryRun:
            "The library changed after this dry run. Choose the legacy bundle again to review an updated import plan."
        case .sourceLibraryInvalid:
            "The current library could not be copied safely because its database or authoritative assets failed validation. Run Check Library Integrity and try again."
        case .stagingFailed:
            "iEvelyn could not construct and validate a complete temporary imported library. The current library was not changed."
        case .atomicSwapFailed:
            "iEvelyn could not atomically activate the imported library. The current library was not changed."
        }
    }
}

actor LegacyImportService {
    private let repository: GRDBLibraryRepository
    private let renderer: any MarkdownRendering
    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let beforeDatabaseCommit: @Sendable () throws -> Void

    init(
        repository: GRDBLibraryRepository,
        renderer: any MarkdownRendering = MarkdownRenderingService(),
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { .now },
        beforeDatabaseCommit: @escaping @Sendable () throws -> Void = { }
    ) {
        self.repository = repository
        self.renderer = renderer
        self.fileManager = fileManager
        self.now = now
        self.beforeDatabaseCommit = beforeDatabaseCommit
    }

    func prepareImport(from sourceURL: URL) async throws -> LegacyImportPlan {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        let data: Data
        do {
            data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        } catch {
            throw LegacyImportError.invalidArchive
        }
        return try await prepareImport(from: data)
    }

    func prepareImport(from archiveData: Data) async throws -> LegacyImportPlan {
        guard repository.database.location.databaseURL != nil else {
            throw LegacyImportError.unavailableForCurrentLibrary
        }
        let bundle = try LegacyBundleReader.readAndValidate(archiveData)
        try Task.checkCancellation()
        let conflicts = Self.findDuplicateConflicts(
            bundleBooks: bundle.books,
            existingBooks: try await repository.fetchLibraryBooks()
        )
        let summary = LegacyImportDryRunSummary(
            sourceSnapshotTimestamp: bundle.manifest.sourceSnapshotTimestamp,
            books: bundle.manifest.counts.books,
            chapters: bundle.manifest.counts.chapters,
            assets: bundle.manifest.counts.assets,
            assetBytes: bundle.manifest.counts.assetBytes,
            exporterWarnings: bundle.warnings.count,
            exporterSkippedItems: bundle.skippedItems.count,
            exporterSkippedCount: bundle.skippedItems.reduce(0) { $0 + $1.count },
            importerWarnings: bundle.importerWarnings.map(\.message),
            duplicateConflicts: conflicts
        )
        return LegacyImportPlan(
            archiveData: archiveData,
            archiveChecksum: Self.sha256(archiveData),
            bundle: bundle,
            summary: summary
        )
    }

    func prepareStagedImport(
        _ plan: LegacyImportPlan,
        duplicateStrategy: LegacyDuplicateStrategy
    ) async throws -> PreparedLegacyImport {
        guard let activeDatabaseURL = repository.database.location.databaseURL else {
            throw LegacyImportError.unavailableForCurrentLibrary
        }
        guard Self.sha256(plan.archiveData) == plan.archiveChecksum else {
            throw LegacyImportError.checksumMismatch("selected legacy bundle")
        }

        let activeRoot = activeDatabaseURL.deletingLastPathComponent()
        let stagedRoot = activeRoot.deletingLastPathComponent().appending(
            path: ".iEvelyn-import-\(UUID().databaseString)",
            directoryHint: .isDirectory
        )
        var candidateDatabase: LibraryDatabase?
        var completed = false
        defer {
            if !completed {
                try? fileManager.removeItem(at: stagedRoot)
            }
        }

        do {
            let currentConflicts = Self.findDuplicateConflicts(
                bundleBooks: plan.bundle.books,
                existingBooks: try await repository.fetchLibraryBooks()
            )
            guard currentConflicts == plan.summary.duplicateConflicts else {
                throw LegacyImportError.libraryChangedSinceDryRun
            }
            try fileManager.createDirectory(at: stagedRoot, withIntermediateDirectories: false)
            let currentAssets = try await copyCurrentDatabase(to: stagedRoot)
            try await copyCurrentAssets(currentAssets, to: stagedRoot)
            try copyCurrentReconciliationReports(from: activeRoot, to: stagedRoot)
            try Task.checkCancellation()

            let conflictIDs = Set(plan.summary.duplicateConflicts.map(\.legacyBookID))
            let selectedBooks = plan.bundle.books.filter { book in
                duplicateStrategy == .importAsNew || !conflictIDs.contains(book.legacyID)
            }
            let plannedImport = try Self.makePlannedImport(
                bundle: plan.bundle,
                selectedBooks: selectedBooks,
                importedAt: now()
            )
            try writeImportedAssets(plannedImport.assets, to: stagedRoot)
            let renderWarnings = try await validateRendering(plannedImport)
            try beforeDatabaseCommit()
            try Task.checkCancellation()

            let database = try LibraryDatabase.makeTemporary(in: stagedRoot)
            candidateDatabase = database
            let searchRepair = try await database.write { database in
                try Self.insert(plannedImport, into: database)
                return try LibrarySearchIndexer.rebuildAll(database)
            }
            let candidateRepository = GRDBLibraryRepository(
                database: database,
                assetStore: LibraryAssetStore(libraryRootURL: stagedRoot)
            )
            try await Self.validateCandidateLibrary(candidateRepository)

            let report = LegacyReconciliationReport.make(
                plan: plan,
                strategy: duplicateStrategy,
                plannedImport: plannedImport,
                skippedDuplicateIDs: duplicateStrategy == .skipLikelyDuplicates
                    ? conflictIDs.sorted()
                    : [],
                renderWarnings: renderWarnings,
                searchRepair: searchRepair,
                importedAt: now()
            )
            let reportRelativePath = try writeReconciliationReport(report, to: stagedRoot)
            try await database.close()
            candidateDatabase = nil
            completed = true
            return PreparedLegacyImport(
                stagedLibraryRootURL: stagedRoot,
                importedBookCount: plannedImport.books.count,
                importedChapterCount: plannedImport.books.reduce(0) { $0 + $1.chapters.count },
                importedAssetCount: plannedImport.assets.count,
                skippedDuplicateCount: report.counts.skippedDuplicateBooks,
                reconciliationReportRelativePath: reportRelativePath
            )
        } catch is CancellationError {
            if let candidateDatabase {
                try? await candidateDatabase.close()
            }
            throw CancellationError()
        } catch let error as LegacyImportError {
            if let candidateDatabase {
                try? await candidateDatabase.close()
            }
            throw error
        } catch {
            if let candidateDatabase {
                try? await candidateDatabase.close()
            }
            throw LegacyImportError.stagingFailed
        }
    }

    func atomicallySwap(_ preparedImport: PreparedLegacyImport, with activeRootURL: URL) throws {
        let stagedRoot = preparedImport.stagedLibraryRootURL.standardizedFileURL
        let activeRoot = activeRootURL.standardizedFileURL
        guard stagedRoot.deletingLastPathComponent() == activeRoot.deletingLastPathComponent(),
              fileManager.fileExists(atPath: stagedRoot.path),
              fileManager.fileExists(atPath: activeRoot.path) else {
            throw LegacyImportError.atomicSwapFailed
        }

        let result = stagedRoot.path.withCString { stagedPath in
            activeRoot.path.withCString { activePath in
                renamex_np(stagedPath, activePath, UInt32(RENAME_SWAP))
            }
        }
        guard result == 0 else {
            throw LegacyImportError.atomicSwapFailed
        }
    }

    func discardPreparedImport(_ preparedImport: PreparedLegacyImport) {
        try? fileManager.removeItem(at: preparedImport.stagedLibraryRootURL)
    }

    private func copyCurrentDatabase(to stagedRoot: URL) async throws -> [Asset] {
        let snapshotURL = stagedRoot.appending(
            path: LibraryDatabase.productionDatabaseName,
            directoryHint: .notDirectory
        )
        let snapshotQueue = try DatabaseQueue(path: snapshotURL.path)
        var isClosed = false
        defer {
            if !isClosed {
                try? snapshotQueue.close()
            }
        }
        try repository.database.writer.backup(to: snapshotQueue)
        let integrityMessages = try await snapshotQueue.read { database in
            try String.fetchAll(database, sql: "PRAGMA integrity_check")
        }
        let foreignKeyViolations = try await snapshotQueue.read { database in
            try Row.fetchAll(database, sql: "PRAGMA foreign_key_check").count
        }
        guard integrityMessages == ["ok"], foreignKeyViolations == 0 else {
            throw LegacyImportError.sourceLibraryInvalid
        }
        let assets = try await snapshotQueue.read { database in
            try Asset.order(Column("storageRelativePath")).fetchAll(database)
        }
        try snapshotQueue.close()
        isClosed = true
        return assets
    }

    private func copyCurrentAssets(_ assets: [Asset], to stagedRoot: URL) async throws {
        for asset in assets.sorted(by: { $0.storageRelativePath < $1.storageRelativePath }) {
            try Task.checkCancellation()
            guard Self.isSafeAssetPath(asset.storageRelativePath) else {
                throw LegacyImportError.sourceLibraryInvalid
            }
            let data: Data
            do {
                data = try await repository.assetStore.storedData(for: asset)
            } catch {
                throw LegacyImportError.sourceLibraryInvalid
            }
            guard Int64(data.count) == asset.byteCount,
                  Self.sha256(data).caseInsensitiveCompare(asset.checksum) == .orderedSame else {
                throw LegacyImportError.sourceLibraryInvalid
            }
            try Self.write(data, relativePath: asset.storageRelativePath, root: stagedRoot)
        }
    }

    private func copyCurrentReconciliationReports(from activeRoot: URL, to stagedRoot: URL) throws {
        let directoryName = "Migration Reports"
        let sourceDirectory = activeRoot.appending(path: directoryName, directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceDirectory.path, isDirectory: &isDirectory) else {
            return
        }
        guard isDirectory.boolValue else {
            throw LegacyImportError.sourceLibraryInvalid
        }

        let reportURLs = try fileManager.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        for sourceURL in reportURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try Task.checkCancellation()
            guard sourceURL.lastPathComponent.hasPrefix("Legacy Import "),
                  sourceURL.pathExtension.lowercased() == "json" else {
                continue
            }
            let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw LegacyImportError.sourceLibraryInvalid
            }
            let data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
            try Self.write(
                data,
                relativePath: "\(directoryName)/\(sourceURL.lastPathComponent)",
                root: stagedRoot
            )
        }
    }

    private func writeImportedAssets(_ assets: [PlannedLegacyAsset], to root: URL) throws {
        for asset in assets {
            try Task.checkCancellation()
            try Self.write(asset.data, relativePath: asset.record.storageRelativePath, root: root)
        }
    }

    private func validateRendering(_ importPlan: PlannedLegacyImport) async throws -> [String] {
        var warnings: [String] = []
        let assetsByBook = Dictionary(grouping: importPlan.assets.map(\.record), by: \.bookID)
        for book in importPlan.books {
            for chapter in book.chapters {
                try Task.checkCancellation()
                let result = try await renderer.render(
                    MarkdownRenderRequest(
                        markdown: chapter.markdown,
                        bookID: book.record.id,
                        assets: assetsByBook[book.record.id, default: []],
                        mode: .readerHTML,
                        documentTitle: chapter.title,
                        language: "und"
                    )
                )
                warnings.append(contentsOf: result.issues.map {
                    "Legacy chapter \(book.legacyID)/\(book.legacyChapterID(for: chapter.id)): \($0.message)"
                })
            }
        }
        return Array(Set(warnings)).sorted()
    }

    private func writeReconciliationReport(
        _ report: LegacyReconciliationReport,
        to root: URL
    ) throws -> String {
        let directory = root.appending(path: "Migration Reports", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let relativePath = "Migration Reports/Legacy Import \(report.reportID.databaseString).json"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(report)
        try Self.write(data, relativePath: relativePath, root: root)
        return relativePath
    }

    private static func validateCandidateLibrary(
        _ repository: GRDBLibraryRepository
    ) async throws {
        let databaseIsHealthy = try await repository.database.read { database in
            try String.fetchAll(database, sql: "PRAGMA integrity_check") == ["ok"]
                && Row.fetchAll(database, sql: "PRAGMA foreign_key_check").isEmpty
        }
        guard databaseIsHealthy else {
            throw LegacyImportError.stagingFailed
        }
        for asset in try await repository.fetchAssets() {
            guard try await repository.assetStore.verifyChecksum(of: asset) else {
                throw LegacyImportError.stagingFailed
            }
        }
    }

    private static func findDuplicateConflicts(
        bundleBooks: [ValidatedLegacyBook],
        existingBooks: [LibraryBook]
    ) -> [LegacyDuplicateConflict] {
        bundleBooks.compactMap { sourceBook in
            let effectiveTitle = sourceBook.title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? "Untitled Legacy Book \(sourceBook.legacyID)"
            let effectiveAuthor = sourceBook.author?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? "Unknown Author"
            let sourceTitle = LibraryNameNormalizer.normalize(effectiveTitle)
            let sourceAuthor = LibraryNameNormalizer.normalize(effectiveAuthor)
            let matches = existingBooks.filter { existing in
                guard LibraryNameNormalizer.normalize(existing.title) == sourceTitle else {
                    return false
                }
                guard !sourceAuthor.isEmpty else { return true }
                let normalizedAuthors = existing.authors.map(LibraryNameNormalizer.normalize)
                return normalizedAuthors.contains(sourceAuthor)
                    || LibraryNameNormalizer.normalize(existing.authors.joined(separator: ", ")) == sourceAuthor
            }
            guard !matches.isEmpty else { return nil }
            return LegacyDuplicateConflict(
                legacyBookID: sourceBook.legacyID,
                title: effectiveTitle,
                author: effectiveAuthor,
                existingBookIDs: matches.map(\.id).sorted { $0.databaseString < $1.databaseString }
            )
        }
        .sorted { $0.legacyBookID < $1.legacyBookID }
    }

    private static func makePlannedImport(
        bundle: ValidatedLegacyBundle,
        selectedBooks: [ValidatedLegacyBook],
        importedAt: Date
    ) throws -> PlannedLegacyImport {
        let assetsByLegacyID = Dictionary(uniqueKeysWithValues: bundle.assets.map { ($0.legacyID, $0) })
        var plannedBooks: [PlannedLegacyBook] = []
        var plannedAssets: [PlannedLegacyAsset] = []
        var bookMappings: [LegacyBookIDMapping] = []
        var chapterMappings: [LegacyChapterIDMapping] = []
        var assetMappings: [LegacyAssetIDMapping] = []

        for sourceBook in selectedBooks.sorted(by: { $0.legacyID < $1.legacyID }) {
            let bookID = UUID()
            let title = sourceBook.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Untitled Legacy Book \(sourceBook.legacyID)"
            let author = sourceBook.author?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Unknown Author"
            var nativeAssetIDs: [Int: UUID] = [:]
            var bookAssets: [Asset] = []
            for legacyAssetID in sourceBook.referencedAssetIDs.sorted() {
                guard let sourceAsset = assetsByLegacyID[legacyAssetID] else {
                    throw LegacyImportError.invalidReference("book \(sourceBook.legacyID) references missing asset \(legacyAssetID)")
                }
                let assetID = UUID()
                nativeAssetIDs[legacyAssetID] = assetID
                let relativePath = "Assets/Books/\(bookID.databaseString)/\(assetID.databaseString).\(sourceAsset.fileExtension)"
                let record = Asset(
                    id: assetID,
                    bookID: bookID,
                    purpose: .chapterImage,
                    mediaType: sourceAsset.mediaType,
                    storageRelativePath: relativePath,
                    checksum: sourceAsset.sha256,
                    byteCount: Int64(sourceAsset.data.count),
                    pixelWidth: sourceAsset.pixelWidth,
                    pixelHeight: sourceAsset.pixelHeight,
                    createdAt: sourceBook.lastUpdated,
                    updatedAt: sourceBook.lastUpdated
                )
                bookAssets.append(record)
                plannedAssets.append(PlannedLegacyAsset(record: record, data: sourceAsset.data))
                assetMappings.append(
                    LegacyAssetIDMapping(
                        legacyAssetID: legacyAssetID,
                        nativeAssetID: assetID,
                        nativeBookID: bookID
                    )
                )
            }

            let replacementURLs = try Dictionary(uniqueKeysWithValues: nativeAssetIDs.map { legacyID, assetID in
                (legacyID, try BookAssetReference(bookID: bookID, assetID: assetID).url().absoluteString)
            })
            var chapters: [Chapter] = []
            var chapterLegacyIDsByNativeID: [UUID: Int] = [:]
            for (position, sourceChapter) in sourceBook.chapters.enumerated() {
                let chapterID = UUID()
                let chapter = Chapter(
                    id: chapterID,
                    bookID: bookID,
                    title: sourceChapter.name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                        ?? "Untitled Chapter \(sourceChapter.legacyID)",
                    markdown: try LegacyFileReferenceRewriter.rewrite(
                        sourceChapter.markdown,
                        replacements: replacementURLs
                    ),
                    position: position,
                    createdAt: sourceChapter.lastUpdated,
                    updatedAt: sourceChapter.lastUpdated
                )
                chapters.append(chapter)
                chapterLegacyIDsByNativeID[chapterID] = sourceChapter.legacyID
                chapterMappings.append(
                    LegacyChapterIDMapping(
                        legacyChapterID: sourceChapter.legacyID,
                        nativeChapterID: chapterID,
                        nativeBookID: bookID
                    )
                )
            }

            let book = Book(
                id: bookID,
                title: title,
                summary: sourceBook.notes ?? "",
                trashedAt: sourceBook.isDeleted ? sourceBook.lastUpdated : nil,
                createdAt: sourceBook.lastUpdated,
                updatedAt: sourceBook.lastUpdated,
                lastOpenedAt: sourceBook.lastViewed
            )
            plannedBooks.append(
                PlannedLegacyBook(
                    legacyID: sourceBook.legacyID,
                    record: book,
                    author: author,
                    chapters: chapters,
                    assets: bookAssets,
                    chapterLegacyIDsByNativeID: chapterLegacyIDsByNativeID
                )
            )
            bookMappings.append(LegacyBookIDMapping(legacyBookID: sourceBook.legacyID, nativeBookID: bookID))
        }

        return PlannedLegacyImport(
            importedAt: importedAt,
            books: plannedBooks,
            assets: plannedAssets,
            bookMappings: bookMappings,
            chapterMappings: chapterMappings,
            assetMappings: assetMappings
        )
    }

    private static func insert(_ importPlan: PlannedLegacyImport, into database: Database) throws {
        for plannedBook in importPlan.books {
            try plannedBook.record.insert(database)
            let normalizedAuthor = LibraryNameNormalizer.normalize(plannedBook.author)
            let author: Author
            if let existing = try Author
                .filter(Column("normalizedName") == normalizedAuthor)
                .fetchOne(database) {
                author = existing
            } else {
                let newAuthor = Author(
                    displayName: plannedBook.author,
                    normalizedName: normalizedAuthor,
                    createdAt: importPlan.importedAt,
                    updatedAt: importPlan.importedAt
                )
                try newAuthor.insert(database)
                author = newAuthor
            }
            try BookAuthor(bookID: plannedBook.record.id, authorID: author.id, position: 0)
                .insert(database)
            for chapter in plannedBook.chapters {
                try chapter.insert(database)
            }
            for asset in plannedBook.assets {
                try asset.insert(database)
            }
        }
    }

    private static func write(_ data: Data, relativePath: String, root: URL) throws {
        guard isSafeAssetPath(relativePath) || relativePath.hasPrefix("Migration Reports/") else {
            throw LegacyImportError.stagingFailed
        }
        let destination = root.appending(path: relativePath, directoryHint: .notDirectory)
        guard destination.isContained(in: root) else {
            throw LegacyImportError.stagingFailed
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw LegacyImportError.stagingFailed
        }
        try data.write(to: destination, options: .atomic)
    }

    private static func isSafeAssetPath(_ path: String) -> Bool {
        LegacyArchivePath.isSafe(path)
            && path.hasPrefix("Assets/Books/")
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated struct ValidatedLegacyBundle: Sendable {
    let manifest: LegacyBundleManifestDocument
    let books: [ValidatedLegacyBook]
    let assets: [ValidatedLegacyAsset]
    let sourceCounts: LegacySourceCountsDocument
    let warnings: [LegacyWarningDocument]
    let skippedItems: [LegacySkippedItemDocument]
    let importerWarnings: [LegacyValidationWarning]
}

nonisolated struct ValidatedLegacyBook: Sendable {
    let legacyID: Int
    let title: String
    let author: String?
    let notes: String?
    let lastUpdated: Date
    let lastViewed: Date?
    let isDeleted: Bool
    let chapters: [ValidatedLegacyChapter]
    let referencedAssetIDs: [Int]
}

nonisolated struct ValidatedLegacyChapter: Sendable {
    let legacyID: Int
    let legacyNumber: Int
    let name: String
    let lastUpdated: Date
    let markdown: String
    let referencedAssetIDs: [Int]
}

nonisolated struct ValidatedLegacyAsset: Sendable {
    let legacyID: Int
    let originalName: String
    let declaredContentType: String
    let mediaType: String
    let fileExtension: String
    let sha256: String
    let pixelWidth: Int
    let pixelHeight: Int
    let data: Data
}

nonisolated struct LegacyValidationWarning: Codable, Equatable, Sendable {
    let code: String
    let entityType: String
    let legacyID: Int?
    let message: String
}

nonisolated private struct PlannedLegacyImport: Sendable {
    let importedAt: Date
    let books: [PlannedLegacyBook]
    let assets: [PlannedLegacyAsset]
    let bookMappings: [LegacyBookIDMapping]
    let chapterMappings: [LegacyChapterIDMapping]
    let assetMappings: [LegacyAssetIDMapping]
}

nonisolated private struct PlannedLegacyBook: Sendable {
    let legacyID: Int
    let record: Book
    let author: String
    let chapters: [Chapter]
    let assets: [Asset]
    let chapterLegacyIDsByNativeID: [UUID: Int]

    func legacyChapterID(for nativeID: UUID) -> Int {
        chapterLegacyIDsByNativeID[nativeID] ?? 0
    }
}

nonisolated private struct PlannedLegacyAsset: Sendable {
    let record: Asset
    let data: Data
}

nonisolated struct LegacyBundleManifestDocument: Codable, Equatable, Sendable {
    let formatIdentifier: String
    let formatVersion: Int
    let sourceSnapshotTimestamp: String
    let producer: LegacyProducerDocument
    let source: LegacySourceDocument
    let counts: LegacyExportCountsDocument
    let assets: [LegacyManifestAssetDocument]
    let files: [LegacyManifestFileDocument]
}

nonisolated struct LegacyProducerDocument: Codable, Equatable, Sendable {
    let name: String
    let version: String
    let runtime: String
}

nonisolated struct LegacySourceDocument: Codable, Equatable, Sendable {
    let kind: String
    let schemaVersion: String
    let selectedBookIds: [Int]
}

nonisolated struct LegacyExportCountsDocument: Codable, Equatable, Sendable {
    let books: Int
    let chapters: Int
    let assets: Int
    let assetBytes: Int64
    let warnings: Int
    let skippedItems: Int
}

nonisolated struct LegacyManifestAssetDocument: Codable, Equatable, Sendable {
    let legacyId: Int
    let originalName: String
    let contentType: String
    let path: String
    let byteCount: Int64
    let sha256: String
}

nonisolated struct LegacyManifestFileDocument: Codable, Equatable, Sendable {
    let path: String
    let byteCount: Int64
    let sha256: String
}

nonisolated struct LegacyBookDocument: Codable, Equatable, Sendable {
    let legacyId: Int
    let title: String
    let author: String?
    let notes: String?
    let lastUpdated: String
    let lastViewed: String?
    let isDeleted: Bool
    let chapters: [LegacyChapterDocument]
    let referencedAssetIds: [Int]
}

nonisolated struct LegacyChapterDocument: Codable, Equatable, Sendable {
    let legacyId: Int
    let legacyNumber: Int
    let name: String
    let lastUpdated: String
    let markdownPath: String
    let referencedAssetIds: [Int]
}

nonisolated struct LegacySourceCountsDocument: Codable, Equatable, Sendable {
    let books: Int
    let selectedBooks: Int
    let chapters: Int
    let selectedChapters: Int
    let files: Int
    let users: Int
    let bookmarks: Int
    let manualBookmarks: Int
    let automaticProgressRecords: Int
}

nonisolated struct LegacyWarningDocument: Codable, Equatable, Sendable {
    let code: String
    let entityType: String
    let legacyId: Int?
    let message: String
}

nonisolated struct LegacySkippedItemDocument: Codable, Equatable, Sendable {
    let code: String
    let entityType: String
    let legacyId: Int?
    let count: Int
    let reason: String
}

nonisolated struct LegacyIDMappingDocument: Codable, Equatable, Sendable {
    let books: [LegacyIDPathDocument]
    let chapters: [LegacyIDPathDocument]
    let assets: [LegacyIDPathDocument]
}

nonisolated struct LegacyIDPathDocument: Codable, Equatable, Sendable {
    let legacyId: Int
    let path: String
}

nonisolated private enum LegacyBundleReader {
    private static let manifestPath = "manifest.json"
    private static let sourceCountsPath = "reports/source-counts.json"
    private static let exportCountsPath = "reports/export-counts.json"
    private static let warningsPath = "reports/warnings.json"
    private static let skippedItemsPath = "reports/skipped-items.json"
    private static let mappingPath = "reports/legacy-id-mapping.json"
    private static let maximumManifestBytes: UInt64 = 5 * 1_024 * 1_024
    private static let maximumJSONBytes: UInt64 = 50 * 1_024 * 1_024

    static func readAndValidate(_ data: Data) throws -> ValidatedLegacyBundle {
        let archive: Archive
        do {
            archive = try Archive(data: data, accessMode: .read)
        } catch {
            throw LegacyImportError.invalidArchive
        }
        var entriesByPath: [String: Entry] = [:]
        for entry in archive {
            guard entry.type == .file,
                  LegacyArchivePath.isSafe(entry.path),
                  entriesByPath.updateValue(entry, forKey: entry.path) == nil else {
                throw LegacyImportError.unsafeOrUnexpectedEntry(entry.path)
            }
        }
        guard let manifestEntry = entriesByPath[manifestPath] else {
            throw LegacyImportError.missingManifest
        }
        guard manifestEntry.uncompressedSize <= maximumManifestBytes else {
            throw LegacyImportError.invalidManifest
        }
        let manifest: LegacyBundleManifestDocument = try decodeJSON(
            LegacyBundleManifestDocument.self,
            path: manifestPath,
            data: try extract(manifestEntry, from: archive)
        )
        guard manifest.formatIdentifier == LegacyMigrationBundleType.formatIdentifier,
              manifest.formatVersion > 0,
              manifest.counts.isNonnegative,
              manifest.assets.count == manifest.counts.assets,
              isSortedUnique(manifest.source.selectedBookIds),
              manifest.source.selectedBookIds.allSatisfy({ $0 > 0 }) else {
            throw LegacyImportError.invalidManifest
        }
        guard manifest.formatVersion == LegacyMigrationBundleType.currentFormatVersion else {
            throw LegacyImportError.unsupportedFormatVersion(manifest.formatVersion)
        }
        _ = try parseDate(manifest.sourceSnapshotTimestamp, path: manifestPath)

        let fileMetadata = try uniqueFileMetadata(manifest.files)
        let expectedPaths = Set([manifestPath] + manifest.files.map(\.path))
        let actualPaths = Set(entriesByPath.keys)
        if let missing = expectedPaths.subtracting(actualPaths).sorted().first {
            throw LegacyImportError.missingEntry(missing)
        }
        guard expectedPaths == actualPaths else {
            throw LegacyImportError.unsafeOrUnexpectedEntry(
                actualPaths.subtracting(expectedPaths).sorted().first ?? "unknown"
            )
        }

        var files: [String: Data] = [:]
        for metadata in fileMetadata.values.sorted(by: { $0.path < $1.path }) {
            guard metadata.byteCount >= 0,
                  let entry = entriesByPath[metadata.path] else {
                throw LegacyImportError.invalidManifest
            }
            guard entry.uncompressedSize == UInt64(metadata.byteCount) else {
                throw LegacyImportError.fileSizeMismatch(metadata.path)
            }
            let extracted = try extract(entry, from: archive)
            guard Int64(extracted.count) == metadata.byteCount else {
                throw LegacyImportError.fileSizeMismatch(metadata.path)
            }
            guard LegacyImportService.sha256(extracted) == metadata.sha256.lowercased() else {
                throw LegacyImportError.checksumMismatch(metadata.path)
            }
            files[metadata.path] = extracted
        }

        let sourceCounts: LegacySourceCountsDocument = try decodeReport(
            LegacySourceCountsDocument.self,
            path: sourceCountsPath,
            files: files
        )
        let exportCounts: LegacyExportCountsDocument = try decodeReport(
            LegacyExportCountsDocument.self,
            path: exportCountsPath,
            files: files
        )
        let warnings: [LegacyWarningDocument] = try decodeReport(
            [LegacyWarningDocument].self,
            path: warningsPath,
            files: files
        )
        let skippedItems: [LegacySkippedItemDocument] = try decodeReport(
            [LegacySkippedItemDocument].self,
            path: skippedItemsPath,
            files: files
        )
        let mapping: LegacyIDMappingDocument = try decodeReport(
            LegacyIDMappingDocument.self,
            path: mappingPath,
            files: files
        )
        guard exportCounts == manifest.counts,
              warnings.count == manifest.counts.warnings,
              skippedItems.count == manifest.counts.skippedItems,
              sourceCounts.selectedBooks == manifest.counts.books,
              sourceCounts.isNonnegative,
              skippedItems.allSatisfy({ $0.count >= 0 }) else {
            throw LegacyImportError.countMismatch
        }

        let manifestAssets = try validateManifestAssets(manifest.assets, files: files)
        var importerWarnings: [LegacyValidationWarning] = []
        let assets = try manifestAssets.map { metadata in
            let data = try requiredFile(metadata.path, files: files)
            let inspected = try LegacyMediaInspector.inspect(data, legacyID: metadata.legacyId)
            if metadata.contentType.caseInsensitiveCompare(inspected.mediaType) != .orderedSame {
                importerWarnings.append(
                    LegacyValidationWarning(
                        code: "asset-media-type-corrected",
                        entityType: "asset",
                        legacyID: metadata.legacyId,
                        message: "Legacy asset \(metadata.legacyId) declared \(metadata.contentType), but its bytes are \(inspected.mediaType); the verified type will be stored."
                    )
                )
            }
            return ValidatedLegacyAsset(
                legacyID: metadata.legacyId,
                originalName: metadata.originalName,
                declaredContentType: metadata.contentType,
                mediaType: inspected.mediaType,
                fileExtension: inspected.fileExtension,
                sha256: metadata.sha256.lowercased(),
                pixelWidth: inspected.pixelWidth,
                pixelHeight: inspected.pixelHeight,
                data: data
            )
        }
        let manifestAssetIDs = Set(assets.map(\.legacyID))
        let books = try validateBooks(
            mapping: mapping,
            selectedBookIDs: manifest.source.selectedBookIds,
            manifestAssetIDs: manifestAssetIDs,
            files: files,
            importerWarnings: &importerWarnings
        )
        try validateMappings(mapping, books: books, assets: assets)

        let allowedPaths = Set(
            [sourceCountsPath, exportCountsPath, warningsPath, skippedItemsPath, mappingPath]
                + mapping.books.map(\.path)
                + mapping.chapters.map(\.path)
                + mapping.assets.map(\.path)
        )
        guard Set(manifest.files.map(\.path)) == allowedPaths,
              books.count == manifest.counts.books,
              books.reduce(0, { $0 + $1.chapters.count }) == manifest.counts.chapters,
              assets.count == manifest.counts.assets,
              assets.reduce(Int64(0), { $0 + Int64($1.data.count) }) == manifest.counts.assetBytes else {
            throw LegacyImportError.countMismatch
        }

        return ValidatedLegacyBundle(
            manifest: manifest,
            books: books,
            assets: assets,
            sourceCounts: sourceCounts,
            warnings: warnings,
            skippedItems: skippedItems,
            importerWarnings: importerWarnings.sorted { lhs, rhs in
                (lhs.entityType, lhs.legacyID ?? 0, lhs.code) < (rhs.entityType, rhs.legacyID ?? 0, rhs.code)
            }
        )
    }

    private static func validateBooks(
        mapping: LegacyIDMappingDocument,
        selectedBookIDs: [Int],
        manifestAssetIDs: Set<Int>,
        files: [String: Data],
        importerWarnings: inout [LegacyValidationWarning]
    ) throws -> [ValidatedLegacyBook] {
        guard isSortedUnique(mapping.books.map(\.legacyId)),
              isSortedUnique(mapping.chapters.map(\.legacyId)),
              mapping.books.map(\.legacyId) == selectedBookIDs else {
            throw LegacyImportError.invalidReference("legacy ID mappings are not unique and sorted")
        }
        let mappedChapters = Dictionary(uniqueKeysWithValues: mapping.chapters.map { ($0.legacyId, $0.path) })
        var consumedChapterIDs = Set<Int>()
        var books: [ValidatedLegacyBook] = []
        for bookMapping in mapping.books {
            guard bookMapping.legacyId > 0,
                  bookMapping.path == bookPath(bookMapping.legacyId) else {
                throw LegacyImportError.invalidReference("book mapping path")
            }
            let document: LegacyBookDocument = try decodeJSON(
                LegacyBookDocument.self,
                path: bookMapping.path,
                data: try requiredFile(bookMapping.path, files: files)
            )
            guard document.legacyId == bookMapping.legacyId,
                  isSortedUnique(document.referencedAssetIds),
                  document.referencedAssetIds.allSatisfy(manifestAssetIDs.contains) else {
                throw LegacyImportError.invalidReference("book \(bookMapping.legacyId) asset list")
            }
            let sortedChapterDocuments = document.chapters.sorted {
                ($0.legacyNumber, $0.legacyId) < ($1.legacyNumber, $1.legacyId)
            }
            guard document.chapters == sortedChapterDocuments,
                  Set(document.chapters.map(\.legacyId)).count == document.chapters.count else {
                throw LegacyImportError.invalidReference("book \(bookMapping.legacyId) chapter order")
            }

            var chapters: [ValidatedLegacyChapter] = []
            var unionAssetIDs = Set<Int>()
            for chapterDocument in document.chapters {
                guard chapterDocument.legacyId > 0,
                      let mappedPath = mappedChapters[chapterDocument.legacyId],
                      mappedPath == chapterDocument.markdownPath,
                      mappedPath == chapterPath(bookMapping.legacyId, chapterDocument.legacyId),
                      consumedChapterIDs.insert(chapterDocument.legacyId).inserted,
                      isSortedUnique(chapterDocument.referencedAssetIds),
                      chapterDocument.referencedAssetIds.allSatisfy(manifestAssetIDs.contains) else {
                    throw LegacyImportError.invalidReference("chapter \(chapterDocument.legacyId)")
                }
                let markdownData = try requiredFile(chapterDocument.markdownPath, files: files)
                guard let markdown = String(data: markdownData, encoding: .utf8) else {
                    throw LegacyImportError.invalidUTF8(chapterDocument.markdownPath)
                }
                let scannedIDs = try LegacyFileReferenceRewriter.scan(markdown)
                let exportedScannedIDs = scannedIDs.intersection(manifestAssetIDs)
                guard exportedScannedIDs == Set(chapterDocument.referencedAssetIds) else {
                    throw LegacyImportError.invalidReference("chapter \(chapterDocument.legacyId) asset references")
                }
                let unresolvedIDs = scannedIDs.subtracting(manifestAssetIDs).sorted()
                if !unresolvedIDs.isEmpty {
                    importerWarnings.append(
                        LegacyValidationWarning(
                            code: "unresolved-legacy-asset-reference",
                            entityType: "chapter",
                            legacyID: chapterDocument.legacyId,
                            message: "Legacy chapter \(chapterDocument.legacyId) retains unavailable asset reference(s): \(unresolvedIDs.map(String.init).joined(separator: ", "))."
                        )
                    )
                }
                let lastUpdated = try parseDate(chapterDocument.lastUpdated, path: bookMapping.path)
                if chapterDocument.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    importerWarnings.append(
                        LegacyValidationWarning(
                            code: "empty-chapter-name-repaired",
                            entityType: "chapter",
                            legacyID: chapterDocument.legacyId,
                            message: "Legacy chapter \(chapterDocument.legacyId) has an empty name and will use a stable fallback title."
                        )
                    )
                }
                unionAssetIDs.formUnion(chapterDocument.referencedAssetIds)
                chapters.append(
                    ValidatedLegacyChapter(
                        legacyID: chapterDocument.legacyId,
                        legacyNumber: chapterDocument.legacyNumber,
                        name: chapterDocument.name,
                        lastUpdated: lastUpdated,
                        markdown: markdown,
                        referencedAssetIDs: chapterDocument.referencedAssetIds
                    )
                )
            }
            guard unionAssetIDs == Set(document.referencedAssetIds) else {
                throw LegacyImportError.invalidReference("book \(bookMapping.legacyId) asset union")
            }
            if document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                importerWarnings.append(
                    LegacyValidationWarning(
                        code: "empty-book-title-repaired",
                        entityType: "book",
                        legacyID: document.legacyId,
                        message: "Legacy book \(document.legacyId) has an empty title and will use a stable fallback title."
                    )
                )
            }
            if document.author?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                importerWarnings.append(
                    LegacyValidationWarning(
                        code: "missing-author-repaired",
                        entityType: "book",
                        legacyID: document.legacyId,
                        message: "Legacy book \(document.legacyId) has no author and will use Unknown Author."
                    )
                )
            }
            if chapters.isEmpty {
                importerWarnings.append(
                    LegacyValidationWarning(
                        code: "book-without-chapters",
                        entityType: "book",
                        legacyID: document.legacyId,
                        message: "Legacy book \(document.legacyId) has no exportable chapters."
                    )
                )
            }
            books.append(
                ValidatedLegacyBook(
                    legacyID: document.legacyId,
                    title: document.title,
                    author: document.author,
                    notes: document.notes,
                    lastUpdated: try parseDate(document.lastUpdated, path: bookMapping.path),
                    lastViewed: try document.lastViewed.map { try parseDate($0, path: bookMapping.path) },
                    isDeleted: document.isDeleted,
                    chapters: chapters,
                    referencedAssetIDs: document.referencedAssetIds
                )
            )
        }
        guard consumedChapterIDs == Set(mapping.chapters.map(\.legacyId)) else {
            throw LegacyImportError.invalidReference("unowned chapter mapping")
        }
        return books
    }

    private static func validateManifestAssets(
        _ assets: [LegacyManifestAssetDocument],
        files: [String: Data]
    ) throws -> [LegacyManifestAssetDocument] {
        guard isSortedUnique(assets.map(\.legacyId)) else {
            throw LegacyImportError.invalidManifest
        }
        for asset in assets {
            let data = try requiredFile(asset.path, files: files)
            guard asset.legacyId > 0,
                  asset.path == assetPath(asset.legacyId),
                  asset.byteCount >= 0,
                  Int64(data.count) == asset.byteCount,
                  asset.sha256.count == 64,
                  asset.sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
                throw LegacyImportError.invalidManifest
            }
            guard LegacyImportService.sha256(data) == asset.sha256 else {
                throw LegacyImportError.checksumMismatch(asset.path)
            }
        }
        return assets
    }

    private static func validateMappings(
        _ mapping: LegacyIDMappingDocument,
        books: [ValidatedLegacyBook],
        assets: [ValidatedLegacyAsset]
    ) throws {
        let expectedChapterMappings = books
            .flatMap { book in
                book.chapters.map {
                    LegacyIDPathDocument(
                        legacyId: $0.legacyID,
                        path: chapterPath(book.legacyID, $0.legacyID)
                    )
                }
            }
            .sorted { $0.legacyId < $1.legacyId }
        guard mapping.assets == assets.map({ LegacyIDPathDocument(legacyId: $0.legacyID, path: assetPath($0.legacyID)) }),
              mapping.books == books.map({ LegacyIDPathDocument(legacyId: $0.legacyID, path: bookPath($0.legacyID)) }),
              mapping.chapters == expectedChapterMappings else {
            throw LegacyImportError.invalidReference("legacy ID mapping report")
        }
        let referencedAssetIDs = Set(books.flatMap(\.referencedAssetIDs))
        guard referencedAssetIDs == Set(assets.map(\.legacyID)) else {
            throw LegacyImportError.invalidReference("unowned asset mapping")
        }
    }

    private static func uniqueFileMetadata(
        _ metadata: [LegacyManifestFileDocument]
    ) throws -> [String: LegacyManifestFileDocument] {
        var result: [String: LegacyManifestFileDocument] = [:]
        for item in metadata {
            guard LegacyArchivePath.isSafe(item.path),
                  item.path != manifestPath,
                  item.byteCount >= 0,
                  item.sha256.count == 64,
                  item.sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
                  result.updateValue(item, forKey: item.path) == nil else {
                throw LegacyImportError.invalidManifest
            }
        }
        return result
    }

    private static func requiredFile(_ path: String, files: [String: Data]) throws -> Data {
        guard let data = files[path] else {
            throw LegacyImportError.missingEntry(path)
        }
        return data
    }

    private static func decodeReport<Value: Decodable>(
        _ type: Value.Type,
        path: String,
        files: [String: Data]
    ) throws -> Value {
        let data = try requiredFile(path, files: files)
        guard UInt64(data.count) <= maximumJSONBytes else {
            throw LegacyImportError.invalidJSON(path)
        }
        return try decodeJSON(type, path: path, data: data)
    }

    private static func decodeJSON<Value: Decodable>(
        _ type: Value.Type,
        path: String,
        data: Data
    ) throws -> Value {
        guard String(data: data, encoding: .utf8) != nil else {
            throw LegacyImportError.invalidUTF8(path)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw LegacyImportError.invalidJSON(path)
        }
    }

    private static func extract(_ entry: Entry, from archive: Archive) throws -> Data {
        var data = Data()
        guard entry.uncompressedSize <= UInt64(Int.max) else {
            throw LegacyImportError.invalidArchive
        }
        data.reserveCapacity(Int(entry.uncompressedSize))
        do {
            _ = try archive.extract(entry) { data.append($0) }
            return data
        } catch {
            throw LegacyImportError.invalidArchive
        }
    }

    private static func parseDate(_ value: String, path: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw LegacyImportError.invalidJSON(path)
        }
        return date
    }

    private static func isSortedUnique(_ values: [Int]) -> Bool {
        values == values.sorted() && Set(values).count == values.count
    }

    private static func bookPath(_ id: Int) -> String {
        "books/\(String(format: "%010d", id))/book.json"
    }

    private static func chapterPath(_ bookID: Int, _ chapterID: Int) -> String {
        "books/\(String(format: "%010d", bookID))/chapters/\(String(format: "%010d", chapterID)).md"
    }

    private static func assetPath(_ id: Int) -> String {
        "assets/\(String(format: "%010d", id)).bin"
    }
}

nonisolated private enum LegacyArchivePath {
    static func isSafe(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasSuffix("/"),
              !path.contains("\\"),
              !path.contains("//") else {
            return false
        }
        return path.split(separator: "/").allSatisfy { component in
            component != "." && component != ".." && !component.isEmpty
        }
    }
}

nonisolated private enum LegacyFileReferenceRewriter {
    private static let pattern = #"(?i)(?:https?://[^\s\)\]\}>\"']*?)?(?:~?/)?Files/(?:View|Download)/([0-9]+)(?:[?#&][^\s\)\]\}>\"']*)?(?=$|[\s\)\]\}>\"'])"#

    static func scan(_ markdown: String) throws -> Set<Int> {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        return Set(expression.matches(in: markdown, range: range).compactMap { match in
            guard let idRange = Range(match.range(at: 1), in: markdown) else { return nil }
            return Int(markdown[idRange]).flatMap { $0 > 0 ? $0 : nil }
        })
    }

    static func rewrite(_ markdown: String, replacements: [Int: String]) throws -> String {
        let expression = try NSRegularExpression(pattern: pattern)
        var result = markdown
        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        for match in expression.matches(in: markdown, range: range).reversed() {
            guard let idRange = Range(match.range(at: 1), in: markdown),
                  let id = Int(markdown[idRange]),
                  let replacement = replacements[id],
                  let matchRange = Range(match.range, in: result) else {
                continue
            }
            result.replaceSubrange(matchRange, with: replacement)
        }
        return result
    }
}

nonisolated private struct LegacyInspectedMedia: Sendable {
    let mediaType: String
    let fileExtension: String
    let pixelWidth: Int
    let pixelHeight: Int
}

nonisolated private enum LegacyMediaInspector {
    static func inspect(_ data: Data, legacyID: Int) throws -> LegacyInspectedMedia {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let typeIdentifier = CGImageSourceGetType(source) as String?,
              let type = UTType(typeIdentifier),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              pixelWidth > 0,
              pixelHeight > 0 else {
            throw LegacyImportError.unsupportedMedia(legacyID)
        }

        let mediaType: String
        let fileExtension: String
        if type.conforms(to: .jpeg) {
            mediaType = "image/jpeg"
            fileExtension = "jpg"
        } else if type.conforms(to: .png) {
            mediaType = "image/png"
            fileExtension = "png"
        } else if type.conforms(to: .gif) {
            mediaType = "image/gif"
            fileExtension = "gif"
        } else if type.conforms(to: .heic) {
            mediaType = "image/heic"
            fileExtension = "heic"
        } else if type.identifier == "public.heif" || type.identifier == "public.heif-standard" {
            mediaType = "image/heif"
            fileExtension = "heif"
        } else {
            throw LegacyImportError.unsupportedMedia(legacyID)
        }
        return LegacyInspectedMedia(
            mediaType: mediaType,
            fileExtension: fileExtension,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
    }
}

nonisolated private struct LegacyBookIDMapping: Codable, Sendable {
    let legacyBookID: Int
    let nativeBookID: UUID
}

nonisolated private struct LegacyChapterIDMapping: Codable, Sendable {
    let legacyChapterID: Int
    let nativeChapterID: UUID
    let nativeBookID: UUID
}

nonisolated private struct LegacyAssetIDMapping: Codable, Sendable {
    let legacyAssetID: Int
    let nativeAssetID: UUID
    let nativeBookID: UUID
}

nonisolated private struct LegacyImportReportCounts: Codable, Equatable, Sendable {
    let bundleBooks: Int
    let bundleChapters: Int
    let bundleAssets: Int
    let importedBooks: Int
    let importedChapters: Int
    let importedAssetRecords: Int
    let skippedDuplicateBooks: Int
    let exporterWarnings: Int
    let exporterSkippedItems: Int
    let rebuiltSearchDocuments: Int
    let rerenderedChapters: Int
}

nonisolated private struct LegacyReconciliationReport: Codable, Sendable {
    static let formatIdentifier = "org.cysun.iEvelyn.legacy-import-report"
    static let formatVersion = 1

    let formatIdentifier: String
    let formatVersion: Int
    let reportID: UUID
    let importedAt: String
    let sourceBundleSHA256: String
    let sourceSnapshotTimestamp: String
    let sourceSchemaVersion: String
    let sourceCounts: LegacySourceCountsDocument
    let exportCounts: LegacyExportCountsDocument
    let duplicateStrategy: LegacyDuplicateStrategy
    let counts: LegacyImportReportCounts
    let skippedDuplicateLegacyBookIDs: [Int]
    let bookMappings: [LegacyBookIDMapping]
    let chapterMappings: [LegacyChapterIDMapping]
    let assetMappings: [LegacyAssetIDMapping]
    let exporterWarnings: [LegacyWarningDocument]
    let exporterSkippedItems: [LegacySkippedItemDocument]
    let importerWarnings: [LegacyValidationWarning]
    let renderingWarnings: [String]

    static func make(
        plan: LegacyImportPlan,
        strategy: LegacyDuplicateStrategy,
        plannedImport: PlannedLegacyImport,
        skippedDuplicateIDs: [Int],
        renderWarnings: [String],
        searchRepair: LibrarySearchRepairReport,
        importedAt: Date
    ) -> LegacyReconciliationReport {
        LegacyReconciliationReport(
            formatIdentifier: formatIdentifier,
            formatVersion: formatVersion,
            reportID: UUID(),
            importedAt: importedAt.formatted(.iso8601),
            sourceBundleSHA256: plan.archiveChecksum,
            sourceSnapshotTimestamp: plan.bundle.manifest.sourceSnapshotTimestamp,
            sourceSchemaVersion: plan.bundle.manifest.source.schemaVersion,
            sourceCounts: plan.bundle.sourceCounts,
            exportCounts: plan.bundle.manifest.counts,
            duplicateStrategy: strategy,
            counts: LegacyImportReportCounts(
                bundleBooks: plan.bundle.manifest.counts.books,
                bundleChapters: plan.bundle.manifest.counts.chapters,
                bundleAssets: plan.bundle.manifest.counts.assets,
                importedBooks: plannedImport.books.count,
                importedChapters: plannedImport.books.reduce(0) { $0 + $1.chapters.count },
                importedAssetRecords: plannedImport.assets.count,
                skippedDuplicateBooks: skippedDuplicateIDs.count,
                exporterWarnings: plan.bundle.warnings.count,
                exporterSkippedItems: plan.bundle.skippedItems.count,
                rebuiltSearchDocuments: searchRepair.rebuiltDocumentCount,
                rerenderedChapters: plannedImport.books.reduce(0) { $0 + $1.chapters.count }
            ),
            skippedDuplicateLegacyBookIDs: skippedDuplicateIDs,
            bookMappings: plannedImport.bookMappings.sorted { $0.legacyBookID < $1.legacyBookID },
            chapterMappings: plannedImport.chapterMappings.sorted { $0.legacyChapterID < $1.legacyChapterID },
            assetMappings: plannedImport.assetMappings.sorted {
                ($0.legacyAssetID, $0.nativeBookID.databaseString)
                    < ($1.legacyAssetID, $1.nativeBookID.databaseString)
            },
            exporterWarnings: plan.bundle.warnings,
            exporterSkippedItems: plan.bundle.skippedItems,
            importerWarnings: plan.bundle.importerWarnings,
            renderingWarnings: renderWarnings
        )
    }
}

extension LegacyExportCountsDocument {
    nonisolated fileprivate var isNonnegative: Bool {
        books >= 0
            && chapters >= 0
            && assets >= 0
            && assetBytes >= 0
            && warnings >= 0
            && skippedItems >= 0
    }
}

extension LegacySourceCountsDocument {
    nonisolated fileprivate var isNonnegative: Bool {
        books >= 0
            && selectedBooks >= 0
            && selectedBooks <= books
            && chapters >= 0
            && selectedChapters >= 0
            && selectedChapters <= chapters
            && files >= 0
            && users >= 0
            && bookmarks >= 0
            && manualBookmarks >= 0
            && automaticProgressRecords >= 0
    }
}

extension String {
    nonisolated fileprivate var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
