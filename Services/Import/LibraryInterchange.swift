import CryptoKit
import Darwin
import Foundation
import GRDB
import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

nonisolated struct LibraryBundleCounts: Codable, Equatable, Sendable {
    let books: Int
    let authors: Int
    let bookAuthors: Int
    let chapters: Int
    let assets: Int
    let tags: Int
    let bookTags: Int
    let readingProgress: Int
    let bookmarks: Int
}

nonisolated struct LibraryBundleFileMetadata: Codable, Equatable, Sendable {
    let path: String
    let byteCount: Int64
    let sha256: String
}

nonisolated struct LibraryBundleAssetMetadata: Codable, Equatable, Sendable {
    let id: UUID
    let bookID: UUID
    let path: String
    let mediaType: String
    let byteCount: Int64
    let sha256: String
}

nonisolated struct LibraryBundleManifest: Codable, Equatable, Sendable {
    static let formatIdentifier = "org.cysun.iEvelyn.library-bundle"
    static let currentFormatVersion = 1
    static let manifestPath = "manifest.json"
    static let databasePath = LibraryDatabase.productionDatabaseName

    let formatIdentifier: String
    let formatVersion: Int
    let createdAt: String
    let appVersion: String
    let appBuild: String
    let counts: LibraryBundleCounts
    let database: LibraryBundleFileMetadata
    let assets: [LibraryBundleAssetMetadata]
}

nonisolated struct LibraryBackupFile: Equatable, Sendable {
    let data: Data
    let suggestedFilename: String
    let manifest: LibraryBundleManifest
}

nonisolated struct LibraryBackupPresentation: Identifiable, Sendable {
    let id = UUID()
    let file: LibraryBackupFile
}

nonisolated struct PreparedLibraryRestore: Equatable, Sendable {
    let stagedLibraryRootURL: URL
    let manifest: LibraryBundleManifest
}

nonisolated struct LibraryIntegrityReport: Equatable, Sendable {
    let databaseIntegrityMessages: [String]
    let foreignKeyViolationCount: Int
    let counts: LibraryBundleCounts
    let missingAssetIDs: [UUID]
    let corruptAssetIDs: [UUID]
    let orphanedFileCount: Int
    let removedOrphanCount: Int
    let failedRepairCount: Int
    let rebuiltSearchDocumentCount: Int?

    var isHealthy: Bool {
        databaseIntegrityMessages == ["ok"]
            && foreignKeyViolationCount == 0
            && missingAssetIDs.isEmpty
            && corruptAssetIDs.isEmpty
            && orphanedFileCount == 0
            && failedRepairCount == 0
    }

    var humanReadableText: String {
        var lines = [
            "Library Integrity Report",
            "Status: \(isHealthy ? "Healthy" : "Attention required")",
            "Database: \(databaseIntegrityMessages == ["ok"] ? "OK" : databaseIntegrityMessages.joined(separator: "; "))",
            "Foreign-key violations: \(foreignKeyViolationCount)",
            "Records: \(counts.books) books, \(counts.chapters) chapters, \(counts.assets) assets, \(counts.bookmarks) bookmarks",
            "Assets: \(missingAssetIDs.count) missing, \(corruptAssetIDs.count) checksum mismatch, \(orphanedFileCount) orphaned",
        ]
        if removedOrphanCount > 0 || failedRepairCount > 0 {
            lines.append("Repair: removed \(removedOrphanCount) orphaned file(s); \(failedRepairCount) removal(s) failed")
        }
        if let rebuiltSearchDocumentCount {
            lines.append("Search repair: rebuilt \(rebuiltSearchDocumentCount) document(s)")
        }
        if !missingAssetIDs.isEmpty {
            lines.append("Missing asset IDs: \(missingAssetIDs.map(\.databaseString).joined(separator: ", "))")
        }
        if !corruptAssetIDs.isEmpty {
            lines.append("Corrupt asset IDs: \(corruptAssetIDs.map(\.databaseString).joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }
}

nonisolated enum LibraryInterchangeError: LocalizedError, Equatable, Sendable {
    case unavailableForCurrentLibrary
    case databaseIntegrityFailed
    case missingAsset(UUID)
    case corruptAsset(UUID)
    case invalidArchive
    case missingManifest
    case invalidManifest
    case unsupportedFormatVersion(Int)
    case unsafeOrUnexpectedEntry(String)
    case missingEntry(String)
    case fileSizeMismatch(String)
    case checksumMismatch(String)
    case countMismatch
    case databaseValidationFailed
    case restoreStagingFailed
    case atomicSwapFailed
    case markdownExportRequiresActiveBook
    case markdownExportRequiresAuthors
    case markdownExportRequiresChapters

    var errorDescription: String? {
        switch self {
        case .unavailableForCurrentLibrary:
            "This operation requires the on-disk iEvelyn library."
        case .databaseIntegrityFailed:
            "The library database did not pass its integrity checks. Run Check Library Integrity before backing up."
        case .missingAsset:
            "A referenced library asset is missing. Replace or remove the affected asset before backing up."
        case .corruptAsset:
            "A referenced library asset no longer matches its stored checksum. Replace the affected asset before backing up."
        case .invalidArchive:
            "The selected file is not a valid iEvelyn library bundle."
        case .missingManifest:
            "The library bundle does not contain manifest.json."
        case .invalidManifest:
            "The library bundle manifest is invalid or does not describe an iEvelyn library."
        case .unsupportedFormatVersion(let version):
            "This library bundle uses unsupported format version \(version). Update iEvelyn before restoring it."
        case .unsafeOrUnexpectedEntry:
            "The library bundle contains an unsafe or unexpected file and was rejected."
        case .missingEntry(let path):
            "The library bundle is missing the required file \(path)."
        case .fileSizeMismatch(let path):
            "The file \(path) does not match the size recorded in the bundle manifest."
        case .checksumMismatch(let path):
            "The file \(path) does not match the checksum recorded in the bundle manifest."
        case .countMismatch:
            "The restored database record counts do not match the bundle manifest."
        case .databaseValidationFailed:
            "The restored database did not pass its integrity and relationship checks."
        case .restoreStagingFailed:
            "iEvelyn could not construct a complete temporary library from the selected bundle. The current library was not changed."
        case .atomicSwapFailed:
            "iEvelyn could not atomically replace the active library. The current library was not changed."
        case .markdownExportRequiresActiveBook:
            "Restore this book before exporting its Markdown source."
        case .markdownExportRequiresAuthors:
            "Add at least one author before exporting this book's Markdown source."
        case .markdownExportRequiresChapters:
            "This book has no chapters to export."
        }
    }
}

nonisolated struct LibraryBackupDocument: FileDocument {
    static let contentType = UTType(
        exportedAs: LibraryBundleManifest.formatIdentifier,
        conformingTo: .zip
    )

    static var readableContentTypes: [UTType] { [contentType] }
    static var writableContentTypes: [UTType] { [contentType] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

nonisolated struct MarkdownExportFile: Equatable, Sendable {
    let data: Data
    let suggestedFilename: String
}

nonisolated struct MarkdownExportPresentation: Identifiable, Sendable {
    let id = UUID()
    let file: MarkdownExportFile
}

nonisolated struct MarkdownExportDocument: FileDocument {
    static let contentType = UTType(filenameExtension: "md") ?? .plainText

    static var readableContentTypes: [UTType] { [contentType, .plainText] }
    static var writableContentTypes: [UTType] { [contentType] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

nonisolated protocol MarkdownExporting: Sendable {
    func exportMarkdown(book: LibraryBook) async throws -> MarkdownExportFile
}

actor MarkdownInterchangeService: MarkdownExporting {
    private let repository: any LibraryRepository

    init(repository: any LibraryRepository) {
        self.repository = repository
    }

    func exportMarkdown(book: LibraryBook) async throws -> MarkdownExportFile {
        guard !book.isTrashed else {
            throw LibraryInterchangeError.markdownExportRequiresActiveBook
        }
        guard !book.authors.isEmpty else {
            throw LibraryInterchangeError.markdownExportRequiresAuthors
        }
        let chapters = try await repository.chapters(forBookID: book.id)
        guard !chapters.isEmpty else {
            throw LibraryInterchangeError.markdownExportRequiresChapters
        }
        try Task.checkCancellation()

        var sections = ["# \(book.title.trimmingCharacters(in: .whitespacesAndNewlines))"]
        sections.append(contentsOf: book.authors.map {
            "### Author: \($0.trimmingCharacters(in: .whitespacesAndNewlines))"
        })
        sections.append(contentsOf: chapters.map(Self.completeChapterMarkdown))
        let source = sections.joined(separator: "\n\n") + "\n"
        return MarkdownExportFile(
            data: Data(source.utf8),
            suggestedFilename: Self.suggestedFilename(for: book.title)
        )
    }

    private static func completeChapterMarkdown(_ chapter: Chapter) -> String {
        let markdown = chapter.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstLine = markdown.split(separator: "\n", maxSplits: 1).first,
              firstLine.hasPrefix("## ") || firstLine.hasPrefix("##\t") else {
            return markdown.isEmpty
                ? "## \(chapter.title)"
                : "## \(chapter.title)\n\n\(markdown)"
        }
        return markdown
    }

    private static func suggestedFilename(for title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:").union(.controlCharacters)
        let sanitized = String(title.unicodeScalars.map { scalar -> Character in
            invalidCharacters.contains(scalar) ? "-" : Character(String(scalar))
        })
        .split(whereSeparator: \Character.isWhitespace)
        .joined(separator: " ")
        .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let basename = sanitized.isEmpty ? "Untitled Book" : String(sanitized.prefix(120))
        return "\(basename).md"
    }
}

actor LibraryInterchangeService {
    private let repository: GRDBLibraryRepository
    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let appVersion: String
    private let appBuild: String

    init(
        repository: GRDBLibraryRepository,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { .now },
        appVersion: String? = nil,
        appBuild: String? = nil
    ) {
        self.repository = repository
        self.fileManager = fileManager
        self.now = now
        self.appVersion = appVersion
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "unknown"
        self.appBuild = appBuild
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "unknown"
    }

    func createBackup() async throws -> LibraryBackupFile {
        let temporaryRoot = fileManager.temporaryDirectory
            .appending(path: "iEvelyn-Backup-\(UUID().databaseString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let snapshotURL = temporaryRoot.appending(
            path: LibraryBundleManifest.databasePath,
            directoryHint: .notDirectory
        )
        let snapshotQueue = try DatabaseQueue(path: snapshotURL.path)
        var snapshotIsClosed = false
        defer {
            if !snapshotIsClosed {
                try? snapshotQueue.close()
            }
        }

        try repository.database.writer.backup(to: snapshotQueue)
        try Task.checkCancellation()
        let inspection = try await snapshotQueue.read(LibraryDatabaseInspection.inspect)
        guard inspection.isDatabaseHealthy else {
            throw LibraryInterchangeError.databaseIntegrityFailed
        }
        let assets = try await snapshotQueue.read { database in
            try Asset.order(Column("storageRelativePath")).fetchAll(database)
        }
        try snapshotQueue.close()
        snapshotIsClosed = true

        let databaseData = try Data(contentsOf: snapshotURL, options: .mappedIfSafe)
        let assetEntries = try await backupAssetEntries(for: assets)
        let manifest = LibraryBundleManifest(
            formatIdentifier: LibraryBundleManifest.formatIdentifier,
            formatVersion: LibraryBundleManifest.currentFormatVersion,
            createdAt: Self.timestamp(now()),
            appVersion: appVersion,
            appBuild: appBuild,
            counts: inspection.counts,
            database: LibraryBundleFileMetadata(
                path: LibraryBundleManifest.databasePath,
                byteCount: Int64(databaseData.count),
                sha256: Self.sha256(databaseData)
            ),
            assets: assetEntries.map(\.metadata)
        )
        let manifestData = try Self.encodeManifest(manifest)
        let archiveEntries = [
            LibraryBundleArchiveEntry(path: LibraryBundleManifest.manifestPath, data: manifestData),
            LibraryBundleArchiveEntry(path: LibraryBundleManifest.databasePath, data: databaseData),
        ] + assetEntries.map {
            LibraryBundleArchiveEntry(path: $0.metadata.path, data: $0.data)
        }
        let archiveData = try LibraryBundleArchive.makeArchive(entries: archiveEntries)
        return LibraryBackupFile(
            data: archiveData,
            suggestedFilename: Self.backupFilename(createdAt: now()),
            manifest: manifest
        )
    }

    func checkAndRepairIntegrity() async throws -> LibraryIntegrityReport {
        let initialInspection = try await repository.database.read(LibraryDatabaseInspection.inspect)
        let assets = try await repository.fetchAssets()
        var missingAssetIDs: [UUID] = []
        var corruptAssetIDs: [UUID] = []
        for asset in assets.sorted(by: { $0.id.databaseString < $1.id.databaseString }) {
            do {
                guard try await repository.assetStore.verifyChecksum(of: asset) else {
                    corruptAssetIDs.append(asset.id)
                    continue
                }
            } catch {
                missingAssetIDs.append(asset.id)
            }
        }

        var removedOrphanCount = 0
        var failedRepairCount = 0
        var rebuiltSearchDocumentCount: Int?
        if initialInspection.isDatabaseHealthy {
            let repair = await repository.assetStore.repair(referencedAssets: assets)
            removedOrphanCount = repair.removedOrphanCount
            failedRepairCount = repair.failedRemovalCount
            rebuiltSearchDocumentCount = try await repository.rebuildSearchIndex().rebuiltDocumentCount
        }
        let finalAudit = await repository.assetStore.audit(referencedAssets: assets)
        let finalInspection = try await repository.database.read(LibraryDatabaseInspection.inspect)
        return LibraryIntegrityReport(
            databaseIntegrityMessages: finalInspection.integrityMessages,
            foreignKeyViolationCount: finalInspection.foreignKeyViolationCount,
            counts: finalInspection.counts,
            missingAssetIDs: missingAssetIDs,
            corruptAssetIDs: corruptAssetIDs,
            orphanedFileCount: finalAudit.orphanedRelativePaths.count,
            removedOrphanCount: removedOrphanCount,
            failedRepairCount: failedRepairCount,
            rebuiltSearchDocumentCount: rebuiltSearchDocumentCount
        )
    }

    func prepareRestore(from sourceURL: URL) async throws -> PreparedLibraryRestore {
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
            throw LibraryInterchangeError.invalidArchive
        }
        return try await prepareRestore(from: data)
    }

    func prepareRestore(from archiveData: Data) async throws -> PreparedLibraryRestore {
        guard let activeRoot = repository.database.location.databaseURL?.deletingLastPathComponent() else {
            throw LibraryInterchangeError.unavailableForCurrentLibrary
        }
        let contents = try LibraryBundleArchive.readAndValidate(archiveData)
        let stagedRoot = activeRoot.deletingLastPathComponent().appending(
            path: ".iEvelyn-restore-\(UUID().databaseString)",
            directoryHint: .isDirectory
        )
        var completed = false
        defer {
            if !completed {
                try? fileManager.removeItem(at: stagedRoot)
            }
        }

        do {
            try fileManager.createDirectory(at: stagedRoot, withIntermediateDirectories: false)
            for entry in contents.files {
                try Task.checkCancellation()
                let destination = stagedRoot.appending(path: entry.key, directoryHint: .notDirectory)
                guard destination.isContained(in: stagedRoot) else {
                    throw LibraryInterchangeError.unsafeOrUnexpectedEntry(entry.key)
                }
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try entry.value.write(to: destination, options: .atomic)
            }

            let candidateDatabase = try LibraryDatabase.makeTemporary(in: stagedRoot)
            let inspection = try await candidateDatabase.read(LibraryDatabaseInspection.inspect)
            guard inspection.isDatabaseHealthy else {
                throw LibraryInterchangeError.databaseValidationFailed
            }
            guard inspection.counts == contents.manifest.counts else {
                throw LibraryInterchangeError.countMismatch
            }
            let databaseAssets = try await candidateDatabase.read { database in
                try Asset.order(Column("storageRelativePath")).fetchAll(database)
            }
            try Self.validateAssetMetadata(
                databaseAssets,
                manifestAssets: contents.manifest.assets
            )
            let candidateAssetStore = LibraryAssetStore(libraryRootURL: stagedRoot)
            try await candidateAssetStore.prepareLibraryLayout()
            for asset in databaseAssets {
                guard try await candidateAssetStore.verifyChecksum(of: asset) else {
                    throw LibraryInterchangeError.corruptAsset(asset.id)
                }
            }
            try await candidateDatabase.close()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LibraryInterchangeError {
            throw error
        } catch {
            throw LibraryInterchangeError.restoreStagingFailed
        }

        completed = true
        return PreparedLibraryRestore(
            stagedLibraryRootURL: stagedRoot,
            manifest: contents.manifest
        )
    }

    func atomicallySwap(_ preparedRestore: PreparedLibraryRestore, with activeRootURL: URL) throws {
        let stagedRoot = preparedRestore.stagedLibraryRootURL.standardizedFileURL
        let activeRoot = activeRootURL.standardizedFileURL
        guard stagedRoot.deletingLastPathComponent() == activeRoot.deletingLastPathComponent(),
              fileManager.fileExists(atPath: stagedRoot.path),
              fileManager.fileExists(atPath: activeRoot.path) else {
            throw LibraryInterchangeError.atomicSwapFailed
        }

        let result = stagedRoot.path.withCString { stagedPath in
            activeRoot.path.withCString { activePath in
                renamex_np(stagedPath, activePath, UInt32(RENAME_SWAP))
            }
        }
        guard result == 0 else {
            throw LibraryInterchangeError.atomicSwapFailed
        }
    }

    func discardPreparedRestore(_ preparedRestore: PreparedLibraryRestore) {
        try? fileManager.removeItem(at: preparedRestore.stagedLibraryRootURL)
    }

    private func backupAssetEntries(for assets: [Asset]) async throws -> [BackupAssetEntry] {
        var entries: [BackupAssetEntry] = []
        for asset in assets {
            try Task.checkCancellation()
            let data: Data
            do {
                data = try await repository.assetStore.storedData(for: asset)
            } catch {
                throw LibraryInterchangeError.missingAsset(asset.id)
            }
            guard Int64(data.count) == asset.byteCount,
                  Self.sha256(data) == asset.checksum else {
                throw LibraryInterchangeError.corruptAsset(asset.id)
            }
            guard Self.isSafeBundlePath(asset.storageRelativePath),
                  asset.storageRelativePath.hasPrefix("Assets/Books/") else {
                throw LibraryInterchangeError.unsafeOrUnexpectedEntry(asset.storageRelativePath)
            }
            entries.append(
                BackupAssetEntry(
                    metadata: LibraryBundleAssetMetadata(
                        id: asset.id,
                        bookID: asset.bookID,
                        path: asset.storageRelativePath,
                        mediaType: asset.mediaType,
                        byteCount: asset.byteCount,
                        sha256: asset.checksum
                    ),
                    data: data
                )
            )
        }
        return entries.sorted { $0.metadata.path < $1.metadata.path }
    }

    private static func validateAssetMetadata(
        _ databaseAssets: [Asset],
        manifestAssets: [LibraryBundleAssetMetadata]
    ) throws {
        guard databaseAssets.count == manifestAssets.count else {
            throw LibraryInterchangeError.countMismatch
        }
        let manifestByID = Dictionary(uniqueKeysWithValues: manifestAssets.map { ($0.id, $0) })
        guard manifestByID.count == manifestAssets.count else {
            throw LibraryInterchangeError.invalidManifest
        }
        for asset in databaseAssets {
            guard let metadata = manifestByID[asset.id],
                  metadata.bookID == asset.bookID,
                  metadata.path == asset.storageRelativePath,
                  metadata.mediaType == asset.mediaType,
                  metadata.byteCount == asset.byteCount,
                  metadata.sha256 == asset.checksum else {
                throw LibraryInterchangeError.invalidManifest
            }
        }
    }

    fileprivate static func isSafeBundlePath(_ path: String) -> Bool {
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

    private static func encodeManifest(_ manifest: LibraryBundleManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }

    fileprivate static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func backupFilename(createdAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return "iEvelyn Library \(formatter.string(from: createdAt))"
    }
}

nonisolated private struct BackupAssetEntry: Sendable {
    let metadata: LibraryBundleAssetMetadata
    let data: Data
}

nonisolated private struct LibraryDatabaseInspection: Sendable {
    let counts: LibraryBundleCounts
    let integrityMessages: [String]
    let foreignKeyViolationCount: Int

    var isDatabaseHealthy: Bool {
        integrityMessages == ["ok"] && foreignKeyViolationCount == 0
    }

    static func inspect(_ database: Database) throws -> LibraryDatabaseInspection {
        func count(_ table: String) throws -> Int {
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
        }

        return LibraryDatabaseInspection(
            counts: LibraryBundleCounts(
                books: try count("books"),
                authors: try count("authors"),
                bookAuthors: try count("bookAuthors"),
                chapters: try count("chapters"),
                assets: try count("assets"),
                tags: try count("tags"),
                bookTags: try count("bookTags"),
                readingProgress: try count("readingProgress"),
                bookmarks: try count("bookmarks")
            ),
            integrityMessages: try String.fetchAll(database, sql: "PRAGMA integrity_check"),
            foreignKeyViolationCount: try Row.fetchAll(database, sql: "PRAGMA foreign_key_check").count
        )
    }
}

nonisolated private struct LibraryBundleArchiveEntry: Sendable {
    let path: String
    let data: Data
}

nonisolated private struct LibraryBundleContents: Sendable {
    let manifest: LibraryBundleManifest
    let files: [String: Data]
}

nonisolated private enum LibraryBundleArchive {
    private static let deterministicDate = Date(timeIntervalSince1970: 315_532_800)
    private static let maximumManifestSize: UInt64 = 5 * 1_024 * 1_024

    static func makeArchive(entries: [LibraryBundleArchiveEntry]) throws -> Data {
        do {
            let archive = try Archive(accessMode: .create)
            for entry in entries {
                try Task.checkCancellation()
                let data = entry.data
                try archive.addEntry(
                    with: entry.path,
                    type: .file,
                    uncompressedSize: Int64(data.count),
                    modificationDate: deterministicDate,
                    permissions: 0o644,
                    compressionMethod: .deflate,
                    provider: { position, size in
                        guard position >= 0,
                              position <= Int64(data.count),
                              let start = Int(exactly: position) else {
                            throw LibraryInterchangeError.invalidArchive
                        }
                        return data.subdata(in: start..<min(data.count, start + size))
                    }
                )
            }
            guard let data = archive.data else {
                throw LibraryInterchangeError.invalidArchive
            }
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LibraryInterchangeError {
            throw error
        } catch {
            throw LibraryInterchangeError.invalidArchive
        }
    }

    static func readAndValidate(_ data: Data) throws -> LibraryBundleContents {
        let archive: Archive
        do {
            archive = try Archive(data: data, accessMode: .read)
        } catch {
            throw LibraryInterchangeError.invalidArchive
        }
        let entries = Array(archive)
        var entriesByPath: [String: Entry] = [:]
        for entry in entries {
            guard entry.type == .file,
                  LibraryInterchangeService.isSafeBundlePath(entry.path),
                  entriesByPath.updateValue(entry, forKey: entry.path) == nil else {
                throw LibraryInterchangeError.unsafeOrUnexpectedEntry(entry.path)
            }
        }
        guard let manifestEntry = entriesByPath[LibraryBundleManifest.manifestPath] else {
            throw LibraryInterchangeError.missingManifest
        }
        guard manifestEntry.uncompressedSize <= maximumManifestSize else {
            throw LibraryInterchangeError.invalidManifest
        }
        let manifestData = try extract(manifestEntry, from: archive)
        let manifest: LibraryBundleManifest
        do {
            manifest = try JSONDecoder().decode(LibraryBundleManifest.self, from: manifestData)
        } catch {
            throw LibraryInterchangeError.invalidManifest
        }
        guard manifest.formatIdentifier == LibraryBundleManifest.formatIdentifier,
              manifest.formatVersion > 0,
              manifest.database.path == LibraryBundleManifest.databasePath,
              manifest.database.byteCount >= 0,
              manifest.counts.assets == manifest.assets.count else {
            throw LibraryInterchangeError.invalidManifest
        }
        guard manifest.formatVersion <= LibraryBundleManifest.currentFormatVersion else {
            throw LibraryInterchangeError.unsupportedFormatVersion(manifest.formatVersion)
        }
        guard manifest.formatVersion == LibraryBundleManifest.currentFormatVersion else {
            throw LibraryInterchangeError.unsupportedFormatVersion(manifest.formatVersion)
        }

        let expectedPaths = Set(
            [LibraryBundleManifest.manifestPath, manifest.database.path]
                + manifest.assets.map(\.path)
        )
        guard expectedPaths.count == manifest.assets.count + 2 else {
            throw LibraryInterchangeError.invalidManifest
        }
        let actualPaths = Set(entriesByPath.keys)
        if let missing = expectedPaths.subtracting(actualPaths).sorted().first {
            throw LibraryInterchangeError.missingEntry(missing)
        }
        guard actualPaths == expectedPaths else {
            let unexpected = actualPaths.subtracting(expectedPaths).sorted().first ?? "unknown"
            throw LibraryInterchangeError.unsafeOrUnexpectedEntry(unexpected)
        }
        for asset in manifest.assets {
            guard LibraryInterchangeService.isSafeBundlePath(asset.path),
                  asset.path.hasPrefix("Assets/Books/"),
                  asset.byteCount >= 0 else {
                throw LibraryInterchangeError.invalidManifest
            }
        }

        var files: [String: Data] = [:]
        let fileMetadata = [manifest.database] + manifest.assets.map {
            LibraryBundleFileMetadata(path: $0.path, byteCount: $0.byteCount, sha256: $0.sha256)
        }
        for metadata in fileMetadata {
            guard let entry = entriesByPath[metadata.path] else {
                throw LibraryInterchangeError.missingEntry(metadata.path)
            }
            guard entry.uncompressedSize == UInt64(metadata.byteCount) else {
                throw LibraryInterchangeError.fileSizeMismatch(metadata.path)
            }
            let extracted = try extract(entry, from: archive)
            guard Int64(extracted.count) == metadata.byteCount else {
                throw LibraryInterchangeError.fileSizeMismatch(metadata.path)
            }
            guard LibraryInterchangeService.sha256(extracted) == metadata.sha256 else {
                throw LibraryInterchangeError.checksumMismatch(metadata.path)
            }
            files[metadata.path] = extracted
        }
        return LibraryBundleContents(manifest: manifest, files: files)
    }

    private static func extract(_ entry: Entry, from archive: Archive) throws -> Data {
        var data = Data()
        if entry.uncompressedSize <= UInt64(Int.max) {
            data.reserveCapacity(Int(entry.uncompressedSize))
        }
        do {
            _ = try archive.extract(entry) { chunk in
                data.append(chunk)
            }
            return data
        } catch {
            throw LibraryInterchangeError.invalidArchive
        }
    }
}
