import Foundation
import GRDB
import Testing
import UniformTypeIdentifiers
import ZIPFoundation
@testable import iEvelyn

@Suite("Legacy migration bundle import", .serialized)
struct LegacyMigrationImportTests {
    @Test("The registered legacy extension resolves to the imported ZIP type")
    func bundleTypeRegistration() throws {
        let extensionType = try #require(
            UTType(filenameExtension: LegacyMigrationBundleType.filenameExtension, conformingTo: .zip)
        )

        #expect(LegacyMigrationBundleType.contentType.identifier == LegacyMigrationBundleType.typeIdentifier)
        #expect(LegacyMigrationBundleType.contentType.preferredFilenameExtension == "ievelynlegacy")
        #expect(LegacyMigrationBundleType.contentType.conforms(to: .zip))
        #expect(extensionType == LegacyMigrationBundleType.contentType)
    }

    @Test("Dry run validates counts and conflicts without writing, then staged import preserves content and assets")
    func validatedDryRunAndStagedImport() async throws {
        let fixture = try await makeFixture()
        let bundle = try makeLegacyBundle()
        let service = makeService(repository: fixture.repository)

        let plan = try await service.prepareImport(from: bundle)
        #expect(plan.summary.books == 2)
        #expect(plan.summary.chapters == 3)
        #expect(plan.summary.assets == 1)
        #expect(plan.summary.duplicateConflicts.map(\.legacyBookID) == [10])
        #expect(plan.summary.exporterWarnings == 1)
        #expect(plan.summary.exporterSkippedItems == 1)
        #expect(plan.summary.exporterSkippedCount == 2)
        #expect(plan.summary.importerWarnings.contains { $0.contains("verified type") })
        #expect(try await fixture.repository.fetchLibraryBooks().count == 1)

        let prepared = try await service.prepareStagedImport(
            plan,
            duplicateStrategy: .skipLikelyDuplicates
        )
        #expect(prepared.importedBookCount == 1)
        #expect(prepared.importedChapterCount == 2)
        #expect(prepared.importedAssetCount == 1)
        #expect(prepared.skippedDuplicateCount == 1)
        #expect(try await fixture.repository.fetchLibraryBooks().count == 1)

        let stagedDatabase = try LibraryDatabase.makeTemporary(in: prepared.stagedLibraryRootURL)
        let stagedRepository = GRDBLibraryRepository(database: stagedDatabase)
        let stagedBooks = try await stagedRepository.fetchLibraryBooks()
        #expect(stagedBooks.count == 2)
        let importedBook = try #require(stagedBooks.first { $0.title == "迁移书" })
        #expect(importedBook.authors == ["作者甲, 作者乙"])
        #expect(importedBook.lastOpenedAt != nil)

        let chapters = try await stagedRepository.chapters(forBookID: importedBook.id)
        #expect(chapters.map(\.title) == ["第一章", "第二章"])
        #expect(chapters.map(\.position) == [0, 1])
        #expect(chapters[0].markdown.contains("book-asset://\(importedBook.id.databaseString)/"))
        #expect(!chapters[0].markdown.contains("Files/View"))
        #expect(chapters[1].markdown.contains("book-asset://\(importedBook.id.databaseString)/"))

        let assets = try await stagedRepository.assets(forBookID: importedBook.id)
        #expect(assets.count == 1)
        #expect(assets[0].mediaType == "image/png")
        let storedAssetData = try await stagedRepository.assetStore.storedData(for: assets[0])
        let expectedAssetData = try pngData()
        #expect(storedAssetData == expectedAssetData)

        let searchDocumentCount = try await stagedDatabase.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM librarySearchDocuments WHERE bookID = ?",
                arguments: [importedBook.id.databaseString]
            ) ?? 0
        }
        #expect(searchDocumentCount > 2)
        let reportURL = prepared.stagedLibraryRootURL
            .appending(path: prepared.reconciliationReportRelativePath)
        let reportData = try Data(contentsOf: reportURL)
        let report = try #require(
            JSONSerialization.jsonObject(with: reportData) as? [String: Any]
        )
        let reportSourceCounts = try #require(report["sourceCounts"] as? [String: Any])
        #expect(report["sourceBundleSHA256"] as? String == plan.archiveChecksum)
        #expect(reportSourceCounts["bookmarks"] as? Int == 2)

        try await stagedDatabase.close()
        await service.discardPreparedImport(prepared)
        try await closeAndRemove(fixture)
    }

    @Test("Import-as-new duplicates shared assets per book and re-import requires an explicit strategy")
    func importAsNewAndReimportBehavior() async throws {
        let fixture = try await makeFixture()
        let bundle = try makeLegacyBundle()
        let service = makeService(repository: fixture.repository)
        let plan = try await service.prepareImport(from: bundle)
        let prepared = try await service.prepareStagedImport(
            plan,
            duplicateStrategy: .importAsNew
        )
        #expect(prepared.importedBookCount == 2)
        #expect(prepared.importedChapterCount == 3)
        #expect(prepared.importedAssetCount == 2)
        try await fixture.database.close()

        try await service.atomicallySwap(prepared, with: fixture.libraryRootURL)
        await service.discardPreparedImport(prepared)
        let importedDatabase = try LibraryDatabase.makeTemporary(in: fixture.libraryRootURL)
        let importedRepository = GRDBLibraryRepository(database: importedDatabase)
        #expect(try await importedRepository.fetchLibraryBooks().count == 3)
        #expect(try await importedRepository.fetchAssets().count == 2)
        #expect(try reconciliationReports(in: fixture.libraryRootURL).count == 1)

        let reimportService = makeService(repository: importedRepository)
        let reimportPlan = try await reimportService.prepareImport(from: bundle)
        #expect(reimportPlan.summary.duplicateConflicts.map(\.legacyBookID) == [10, 20])
        let skipped = try await reimportService.prepareStagedImport(
            reimportPlan,
            duplicateStrategy: .skipLikelyDuplicates
        )
        #expect(skipped.importedBookCount == 0)
        #expect(skipped.skippedDuplicateCount == 2)

        let skippedDatabase = try LibraryDatabase.makeTemporary(in: skipped.stagedLibraryRootURL)
        let skippedRepository = GRDBLibraryRepository(database: skippedDatabase)
        #expect(try await skippedRepository.fetchLibraryBooks().count == 3)
        #expect(try await skippedRepository.fetchAssets().count == 2)
        #expect(try reconciliationReports(in: skipped.stagedLibraryRootURL).count == 2)
        try await skippedDatabase.close()
        await reimportService.discardPreparedImport(skipped)
        try await importedDatabase.close()
        try? FileManager.default.removeItem(at: fixture.containerURL)
    }

    @Test("Missing, corrupt, future-version, and unsupported-media bundles fail before staging")
    func validationFailuresLeaveLibraryUnchanged() async throws {
        let fixture = try await makeFixture()
        let service = makeService(repository: fixture.repository)
        let originalBundle = try makeLegacyBundle()
        let originalFiles = try archiveFiles(originalBundle)
        let assetPath = "assets/0000000050.bin"

        var missingFiles = originalFiles
        missingFiles.removeValue(forKey: assetPath)
        await #expect(throws: LegacyImportError.missingEntry(assetPath)) {
            try await service.prepareImport(from: makeArchive(files: missingFiles))
        }

        var corruptFiles = originalFiles
        var corruptAsset = try #require(corruptFiles[assetPath])
        corruptAsset[corruptAsset.startIndex] ^= 0xff
        corruptFiles[assetPath] = corruptAsset
        await #expect(throws: LegacyImportError.checksumMismatch(assetPath)) {
            try await service.prepareImport(from: makeArchive(files: corruptFiles))
        }

        var futureFiles = originalFiles
        var manifest = try JSONDecoder().decode(
            LegacyBundleManifestDocument.self,
            from: #require(futureFiles["manifest.json"])
        )
        manifest = LegacyBundleManifestDocument(
            formatIdentifier: manifest.formatIdentifier,
            formatVersion: LegacyMigrationBundleType.currentFormatVersion + 1,
            sourceSnapshotTimestamp: manifest.sourceSnapshotTimestamp,
            producer: manifest.producer,
            source: manifest.source,
            counts: manifest.counts,
            assets: manifest.assets,
            files: manifest.files
        )
        futureFiles["manifest.json"] = try encode(manifest)
        await #expect(
            throws: LegacyImportError.unsupportedFormatVersion(
                LegacyMigrationBundleType.currentFormatVersion + 1
            )
        ) {
            try await service.prepareImport(from: makeArchive(files: futureFiles))
        }

        await #expect(throws: LegacyImportError.unsupportedMedia(50)) {
            try await service.prepareImport(
                from: makeLegacyBundle(assetData: Data("not an image".utf8))
            )
        }

        var inconsistentManifestFiles = originalFiles
        var inconsistentManifest = try JSONDecoder().decode(
            LegacyBundleManifestDocument.self,
            from: #require(inconsistentManifestFiles["manifest.json"])
        )
        let sourceAsset = try #require(inconsistentManifest.assets.first)
        inconsistentManifest = LegacyBundleManifestDocument(
            formatIdentifier: inconsistentManifest.formatIdentifier,
            formatVersion: inconsistentManifest.formatVersion,
            sourceSnapshotTimestamp: inconsistentManifest.sourceSnapshotTimestamp,
            producer: inconsistentManifest.producer,
            source: inconsistentManifest.source,
            counts: inconsistentManifest.counts,
            assets: [
                LegacyManifestAssetDocument(
                    legacyId: sourceAsset.legacyId,
                    originalName: sourceAsset.originalName,
                    contentType: sourceAsset.contentType,
                    path: sourceAsset.path,
                    byteCount: sourceAsset.byteCount,
                    sha256: String(repeating: "0", count: 64)
                )
            ],
            files: inconsistentManifest.files
        )
        inconsistentManifestFiles["manifest.json"] = try encode(inconsistentManifest)
        await #expect(throws: LegacyImportError.checksumMismatch(assetPath)) {
            try await service.prepareImport(from: makeArchive(files: inconsistentManifestFiles))
        }

        #expect(try await fixture.repository.fetchLibraryBooks().count == 1)
        #expect(try importDirectories(beside: fixture.libraryRootURL).isEmpty)
        try await closeAndRemove(fixture)
    }

    @Test("A duplicate-relevant library change invalidates the reviewed dry run")
    func libraryChangeInvalidatesDryRun() async throws {
        let fixture = try await makeFixture()
        let service = makeService(repository: fixture.repository)
        let plan = try await service.prepareImport(from: makeLegacyBundle())

        _ = try await fixture.repository.createBook(
            metadata: BookMetadataInput(
                title: "迁移书",
                authors: ["作者甲, 作者乙"]
            ),
            contentChapters: [
                ImportedBookChapter(title: "Later", markdown: "## Later")
            ],
            coverSourceURL: nil,
            at: Self.importedAt
        )

        await #expect(throws: LegacyImportError.libraryChangedSinceDryRun) {
            try await service.prepareStagedImport(
                plan,
                duplicateStrategy: .skipLikelyDuplicates
            )
        }
        #expect(try importDirectories(beside: fixture.libraryRootURL).isEmpty)
        try await closeAndRemove(fixture)
    }

    @Test("An interrupted staged import cleans up and atomic directory exchange can roll back")
    func stagingFailureAndAtomicRollback() async throws {
        let fixture = try await makeFixture()
        let bundle = try makeLegacyBundle()
        let failingService = LegacyImportService(
            repository: fixture.repository,
            now: { Self.importedAt },
            beforeDatabaseCommit: { throw InjectedImportFailure() }
        )
        let plan = try await failingService.prepareImport(from: bundle)
        await #expect(throws: LegacyImportError.stagingFailed) {
            try await failingService.prepareStagedImport(
                plan,
                duplicateStrategy: .importAsNew
            )
        }
        #expect(try await fixture.repository.fetchLibraryBooks().count == 1)
        #expect(try importDirectories(beside: fixture.libraryRootURL).isEmpty)

        let cancelledService = makeService(repository: fixture.repository)
        let cancellationTask = Task {
            try await cancelledService.prepareStagedImport(
                plan,
                duplicateStrategy: .importAsNew
            )
        }
        cancellationTask.cancel()
        do {
            _ = try await cancellationTask.value
            Issue.record("Expected staged legacy import to be cancelled")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }
        #expect(try importDirectories(beside: fixture.libraryRootURL).isEmpty)

        let service = makeService(repository: fixture.repository)
        let prepared = try await service.prepareStagedImport(
            plan,
            duplicateStrategy: .skipLikelyDuplicates
        )
        let originalMarker = fixture.libraryRootURL.appending(path: "original.marker")
        let importedMarker = prepared.stagedLibraryRootURL.appending(path: "imported.marker")
        try Data("original".utf8).write(to: originalMarker)
        try Data("imported".utf8).write(to: importedMarker)
        try await fixture.database.close()

        try await service.atomicallySwap(prepared, with: fixture.libraryRootURL)
        #expect(FileManager.default.fileExists(atPath: fixture.libraryRootURL.appending(path: "imported.marker").path))
        #expect(FileManager.default.fileExists(atPath: prepared.stagedLibraryRootURL.appending(path: "original.marker").path))

        try await service.atomicallySwap(prepared, with: fixture.libraryRootURL)
        #expect(FileManager.default.fileExists(atPath: originalMarker.path))
        #expect(FileManager.default.fileExists(atPath: importedMarker.path))
        await service.discardPreparedImport(prepared)

        let reopened = try LibraryDatabase.makeTemporary(in: fixture.libraryRootURL)
        let reopenedRepository = GRDBLibraryRepository(database: reopened)
        #expect(try await reopenedRepository.fetchLibraryBooks().count == 1)
        try await reopened.close()
        try? FileManager.default.removeItem(at: fixture.containerURL)
    }

    private func makeFixture() async throws -> LegacyImportFixture {
        let container = FileManager.default.temporaryDirectory.appending(
            path: "iEvelyn-LegacyImportTests-\(UUID().databaseString)",
            directoryHint: .isDirectory
        )
        let root = container.appending(path: "iEvelyn", directoryHint: .isDirectory)
        let database = try LibraryDatabase.makeTemporary(in: root)
        let repository = GRDBLibraryRepository(database: database)
        try await repository.prepareAssetStorage()
        _ = try await repository.createBook(
            metadata: BookMetadataInput(
                title: "Existing Book",
                authors: ["Legacy Author"]
            ),
            contentChapters: [
                ImportedBookChapter(title: "Existing", markdown: "## Existing\n\nOriginal content.")
            ],
            coverSourceURL: nil,
            at: Self.importedAt.addingTimeInterval(-1_000)
        )
        return LegacyImportFixture(
            containerURL: container,
            libraryRootURL: root,
            database: database,
            repository: repository
        )
    }

    private func closeAndRemove(_ fixture: LegacyImportFixture) async throws {
        try await fixture.database.close()
        try? FileManager.default.removeItem(at: fixture.containerURL)
    }

    private func makeService(repository: GRDBLibraryRepository) -> LegacyImportService {
        LegacyImportService(repository: repository, now: { Self.importedAt })
    }

    private func makeLegacyBundle(assetData: Data? = nil) throws -> Data {
        let assetData = try assetData ?? pngData()
        let books = [
            LegacyBookDocument(
                legacyId: 10,
                title: "Existing Book",
                author: "Legacy Author",
                notes: "Duplicate source notes",
                lastUpdated: "2026-08-15T12:00:00+00:00",
                lastViewed: nil,
                isDeleted: false,
                chapters: [
                    LegacyChapterDocument(
                        legacyId: 101,
                        legacyNumber: 1,
                        name: "Opening",
                        lastUpdated: "2026-08-15T12:00:00+00:00",
                        markdownPath: "books/0000000010/chapters/0000000101.md",
                        referencedAssetIds: [50]
                    )
                ],
                referencedAssetIds: [50]
            ),
            LegacyBookDocument(
                legacyId: 20,
                title: "迁移书",
                author: "作者甲, 作者乙",
                notes: "保留的说明",
                lastUpdated: "2026-08-16T12:00:00.125+00:00",
                lastViewed: "2026-08-16T13:00:00+00:00",
                isDeleted: false,
                chapters: [
                    LegacyChapterDocument(
                        legacyId: 201,
                        legacyNumber: 3,
                        name: "第一章",
                        lastUpdated: "2026-08-16T12:00:00+00:00",
                        markdownPath: "books/0000000020/chapters/0000000201.md",
                        referencedAssetIds: [50]
                    ),
                    LegacyChapterDocument(
                        legacyId: 202,
                        legacyNumber: 9,
                        name: "第二章",
                        lastUpdated: "2026-08-16T12:05:00+00:00",
                        markdownPath: "books/0000000020/chapters/0000000202.md",
                        referencedAssetIds: [50]
                    )
                ],
                referencedAssetIds: [50]
            )
        ]
        var payloads: [String: Data] = [
            "books/0000000010/book.json": try encode(books[0]),
            "books/0000000010/chapters/0000000101.md": Data("## Opening\n\n![Shared](/Files/View/50)\n".utf8),
            "books/0000000020/book.json": try encode(books[1]),
            "books/0000000020/chapters/0000000201.md": Data("## 第一章\n\n独特迁移词。\n\n![图](~/files/download/50?raw=1)\n".utf8),
            "books/0000000020/chapters/0000000202.md": Data("## 第二章\n\n![图](https://legacy.test/Files/View/50#page)\n".utf8),
            "assets/0000000050.bin": assetData,
            "reports/source-counts.json": try encode(
                LegacySourceCountsDocument(
                    books: 2,
                    selectedBooks: 2,
                    chapters: 3,
                    selectedChapters: 3,
                    files: 12,
                    users: 1,
                    bookmarks: 2,
                    manualBookmarks: 1,
                    automaticProgressRecords: 1
                )
            ),
            "reports/warnings.json": try encode([
                LegacyWarningDocument(
                    code: "chapter-number-gap",
                    entityType: "book",
                    legacyId: 20,
                    message: "Chapter numbers contain gaps."
                )
            ]),
            "reports/skipped-items.json": try encode([
                LegacySkippedItemDocument(
                    code: "legacy-progress-excluded",
                    entityType: "reading-progress",
                    legacyId: nil,
                    count: 2,
                    reason: "Paragraph-index progress is intentionally excluded."
                )
            ]),
            "reports/legacy-id-mapping.json": try encode(
                LegacyIDMappingDocument(
                    books: [
                        LegacyIDPathDocument(legacyId: 10, path: "books/0000000010/book.json"),
                        LegacyIDPathDocument(legacyId: 20, path: "books/0000000020/book.json")
                    ],
                    chapters: [
                        LegacyIDPathDocument(legacyId: 101, path: "books/0000000010/chapters/0000000101.md"),
                        LegacyIDPathDocument(legacyId: 201, path: "books/0000000020/chapters/0000000201.md"),
                        LegacyIDPathDocument(legacyId: 202, path: "books/0000000020/chapters/0000000202.md")
                    ],
                    assets: [
                        LegacyIDPathDocument(legacyId: 50, path: "assets/0000000050.bin")
                    ]
                )
            )
        ]
        let counts = LegacyExportCountsDocument(
            books: 2,
            chapters: 3,
            assets: 1,
            assetBytes: Int64(assetData.count),
            warnings: 1,
            skippedItems: 1
        )
        payloads["reports/export-counts.json"] = try encode(counts)
        let files = payloads.keys.sorted().map { path in
            let data = payloads[path] ?? Data()
            return LegacyManifestFileDocument(
                path: path,
                byteCount: Int64(data.count),
                sha256: LegacyImportService.sha256(data)
            )
        }
        let manifest = LegacyBundleManifestDocument(
            formatIdentifier: LegacyMigrationBundleType.formatIdentifier,
            formatVersion: LegacyMigrationBundleType.currentFormatVersion,
            sourceSnapshotTimestamp: "2026-08-16T13:00:00+00:00",
            producer: LegacyProducerDocument(name: "EvelynMigration", version: "1.0.0", runtime: ".NET 10"),
            source: LegacySourceDocument(
                kind: "Evelyn.NET PostgreSQL",
                schemaVersion: "fixture-v1",
                selectedBookIds: [10, 20]
            ),
            counts: counts,
            assets: [
                LegacyManifestAssetDocument(
                    legacyId: 50,
                    originalName: "legacy-picture.bin",
                    contentType: "application/octet-stream",
                    path: "assets/0000000050.bin",
                    byteCount: Int64(assetData.count),
                    sha256: LegacyImportService.sha256(assetData)
                )
            ],
            files: files
        )
        payloads["manifest.json"] = try encode(manifest)
        return try makeArchive(files: payloads)
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func archiveFiles(_ data: Data) throws -> [String: Data] {
        let archive = try Archive(data: data, accessMode: .read)
        return try Dictionary(uniqueKeysWithValues: archive.map { entry in
            var extracted = Data()
            _ = try archive.extract(entry) { extracted.append($0) }
            return (entry.path, extracted)
        })
    }

    private func makeArchive(files: [String: Data]) throws -> Data {
        let archive = try Archive(accessMode: .create)
        let orderedPaths = ["manifest.json"] + files.keys.filter { $0 != "manifest.json" }.sorted()
        for path in orderedPaths {
            let data = try #require(files[path])
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: .deflate,
                provider: { position, size in
                    let start = Int(position)
                    return data.subdata(in: start..<min(data.count, start + size))
                }
            )
        }
        return try #require(archive.data)
    }

    private func importDirectories(beside root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: root.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasPrefix(".iEvelyn-import-") }
    }

    private func reconciliationReports(in root: URL) throws -> [URL] {
        let directory = root.appending(path: "Migration Reports", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter {
            $0.lastPathComponent.hasPrefix("Legacy Import ")
                && $0.pathExtension.lowercased() == "json"
        }
    }

    private func pngData() throws -> Data {
        try #require(Data(base64Encoded: Self.onePixelPNG))
    }

    private static let importedAt = Date(timeIntervalSince1970: 1_787_000_000)
    private static let onePixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}

nonisolated private struct LegacyImportFixture: Sendable {
    let containerURL: URL
    let libraryRootURL: URL
    let database: LibraryDatabase
    let repository: GRDBLibraryRepository
}

nonisolated private struct InjectedImportFailure: Error { }
