import Foundation
import GRDB
import Testing
import UniformTypeIdentifiers
import ZIPFoundation
@testable import iEvelyn

@Suite("Library backup, restore, and interchange", .serialized)
struct LibraryInterchangeTests {
    @Test("A backup round trip preserves canonical records, relationships, Markdown, and assets")
    func backupRoundTrip() async throws {
        let fixture = try await makeFixture()
        let service = makeService(repository: fixture.repository)
        let sourceSnapshot = try await snapshot(fixture.database)

        let backup = try await service.createBackup()
        let archive = try Archive(data: backup.data, accessMode: .read)
        let archivePaths = Set(archive.map(\.path))
        let manifestData = try archiveData(at: LibraryBundleManifest.manifestPath, in: archive)
        let decodedManifest = try JSONDecoder().decode(LibraryBundleManifest.self, from: manifestData)

        #expect(backup.suggestedFilename == "iEvelyn Library 2026-08-16")
        #expect(backup.manifest == decodedManifest)
        #expect(decodedManifest.formatIdentifier == LibraryBundleManifest.formatIdentifier)
        #expect(decodedManifest.formatVersion == 1)
        #expect(decodedManifest.appVersion == "1.0-test")
        #expect(decodedManifest.appBuild == "13")
        #expect(decodedManifest.counts.books == 1)
        #expect(decodedManifest.counts.chapters == 2)
        #expect(decodedManifest.counts.assets == 1)
        #expect(decodedManifest.counts.readingProgress == 1)
        #expect(decodedManifest.counts.bookmarks == 1)
        #expect(archivePaths == Set(
            [LibraryBundleManifest.manifestPath, LibraryBundleManifest.databasePath]
                + decodedManifest.assets.map(\.path)
        ))

        let prepared = try await service.prepareRestore(from: backup.data)
        let restoredDatabase = try LibraryDatabase.makeTemporary(in: prepared.stagedLibraryRootURL)
        let restoredSnapshot = try await snapshot(restoredDatabase)
        let restoredRepository = GRDBLibraryRepository(database: restoredDatabase)
        let restoredAssets = try await restoredRepository.fetchAssets()

        #expect(restoredSnapshot == sourceSnapshot)
        #expect(restoredAssets.count == 1)
        #expect(
            try await restoredRepository.assetStore.verifyChecksum(of: #require(restoredAssets.first))
        )
        #expect(
            try await restoredRepository.assetStore.storedData(for: #require(restoredAssets.first))
                == fixture.coverData
        )

        try await restoredDatabase.close()
        await service.discardPreparedRestore(prepared)
        try await fixture.database.close()
        try? FileManager.default.removeItem(at: fixture.containerURL)
    }

    @Test("The registered bundle type maps the custom extension to the exported ZIP type")
    func bundleTypeRegistration() throws {
        let contentType = LibraryBackupDocument.contentType
        let extensionType = try #require(
            UTType(filenameExtension: "ievelynlibrary", conformingTo: .zip)
        )

        #expect(contentType.identifier == LibraryBundleManifest.formatIdentifier)
        #expect(contentType.preferredFilenameExtension == "ievelynlibrary")
        #expect(contentType.conforms(to: .zip))
        #expect(extensionType == contentType)
    }

    @Test("Missing files, corrupt checksums, and future versions are rejected before staging")
    func validationFailuresLeaveCurrentLibraryUnchanged() async throws {
        let fixture = try await makeFixture()
        let service = makeService(repository: fixture.repository)
        let before = try await snapshot(fixture.database)
        let backup = try await service.createBackup()
        let files = try archiveFiles(backup.data)
        let manifest = try decodedManifest(from: files)
        let assetPath = try #require(manifest.assets.first?.path)

        var missingFiles = files
        missingFiles.removeValue(forKey: assetPath)
        let missingBundle = try makeArchive(files: missingFiles)
        await #expect(throws: LibraryInterchangeError.missingEntry(assetPath)) {
            try await service.prepareRestore(from: missingBundle)
        }

        var corruptFiles = files
        var corruptAsset = try #require(corruptFiles[assetPath])
        corruptAsset[corruptAsset.startIndex] ^= 0xff
        corruptFiles[assetPath] = corruptAsset
        let corruptBundle = try makeArchive(files: corruptFiles)
        await #expect(throws: LibraryInterchangeError.checksumMismatch(assetPath)) {
            try await service.prepareRestore(from: corruptBundle)
        }

        var futureFiles = files
        let futureManifest = LibraryBundleManifest(
            formatIdentifier: manifest.formatIdentifier,
            formatVersion: LibraryBundleManifest.currentFormatVersion + 1,
            createdAt: manifest.createdAt,
            appVersion: manifest.appVersion,
            appBuild: manifest.appBuild,
            counts: manifest.counts,
            database: manifest.database,
            assets: manifest.assets
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        futureFiles[LibraryBundleManifest.manifestPath] = try encoder.encode(futureManifest)
        let futureBundle = try makeArchive(files: futureFiles)
        await #expect(
            throws: LibraryInterchangeError.unsupportedFormatVersion(
                LibraryBundleManifest.currentFormatVersion + 1
            )
        ) {
            try await service.prepareRestore(from: futureBundle)
        }

        #expect(try await snapshot(fixture.database) == before)
        #expect(try restoreDirectories(beside: fixture.libraryRootURL).isEmpty)

        try await fixture.database.close()
        try? FileManager.default.removeItem(at: fixture.containerURL)
    }

    @Test("A cancelled restore removes its temporary staging library")
    func cancelledRestoreCleansUp() async throws {
        let fixture = try await makeFixture()
        let service = makeService(repository: fixture.repository)
        let backup = try await service.createBackup()
        let task = Task {
            try await service.prepareRestore(from: backup.data)
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected restore preparation to be cancelled")
        } catch is CancellationError {
            // Expected.
        }
        #expect(try restoreDirectories(beside: fixture.libraryRootURL).isEmpty)

        try await fixture.database.close()
        try? FileManager.default.removeItem(at: fixture.containerURL)
    }

    @Test("The active and staged library directories exchange atomically and can be swapped back")
    func atomicSwapRollback() async throws {
        let fixture = try await makeFixture()
        let service = makeService(repository: fixture.repository)
        let backup = try await service.createBackup()
        let prepared = try await service.prepareRestore(from: backup.data)
        let originalMarker = fixture.libraryRootURL.appending(path: "original.marker")
        let restoredMarker = prepared.stagedLibraryRootURL.appending(path: "restored.marker")
        try Data("original".utf8).write(to: originalMarker)
        try Data("restored".utf8).write(to: restoredMarker)
        try await fixture.database.close()

        try await service.atomicallySwap(prepared, with: fixture.libraryRootURL)
        #expect(FileManager.default.fileExists(atPath: fixture.libraryRootURL.appending(path: "restored.marker").path))
        #expect(FileManager.default.fileExists(atPath: prepared.stagedLibraryRootURL.appending(path: "original.marker").path))

        try await service.atomicallySwap(prepared, with: fixture.libraryRootURL)
        #expect(FileManager.default.fileExists(atPath: originalMarker.path))
        #expect(FileManager.default.fileExists(atPath: restoredMarker.path))

        await service.discardPreparedRestore(prepared)
        let reopened = try LibraryDatabase.makeTemporary(in: fixture.libraryRootURL)
        #expect(try await snapshot(reopened).books.count == 1)
        try await reopened.close()
        try? FileManager.default.removeItem(at: fixture.containerURL)
    }

    @Test("Integrity repair removes orphans, rebuilds search, and reports a healthy library")
    func integrityRepairReport() async throws {
        let fixture = try await makeFixture()
        let orphanURL = fixture.libraryRootURL
            .appending(path: "Assets/Books/orphan.bin", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: orphanURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("orphan".utf8).write(to: orphanURL)

        let report = try await makeService(repository: fixture.repository).checkAndRepairIntegrity()

        #expect(report.isHealthy)
        #expect(report.removedOrphanCount == 1)
        #expect(report.failedRepairCount == 0)
        #expect(report.rebuiltSearchDocumentCount != nil)
        #expect(!FileManager.default.fileExists(atPath: orphanURL.path))
        #expect(report.humanReadableText.contains("Status: Healthy"))
        #expect(report.humanReadableText.contains("Repair: removed 1 orphaned file"))

        try await fixture.database.close()
        try? FileManager.default.removeItem(at: fixture.containerURL)
    }

    @Test("A valid backup can replace a library whose database no longer opens")
    func recoveryRestoreDoesNotRequireAnOpenRepository() async throws {
        let fixture = try await makeFixture()
        let backup = try await makeService(repository: fixture.repository).createBackup()
        try await fixture.database.close()
        let databaseURL = fixture.libraryRootURL.appending(
            path: LibraryDatabase.productionDatabaseName,
            directoryHint: .notDirectory
        )
        try Data("not a SQLite database".utf8).write(to: databaseURL, options: .atomic)

        let recoveryService = LibraryInterchangeService(
            recoveryLibraryRootURL: fixture.libraryRootURL
        )
        let prepared = try await recoveryService.prepareRestore(from: backup.data)
        try await recoveryService.atomicallySwap(prepared, with: fixture.libraryRootURL)

        let recoveredDatabase = try LibraryDatabase.makeTemporary(in: fixture.libraryRootURL)
        #expect(try await snapshot(recoveredDatabase).books.count == 1)
        try await recoveredDatabase.close()
        await recoveryService.discardPreparedRestore(prepared)
        try? FileManager.default.removeItem(at: fixture.containerURL)
    }

    @Test("Markdown export reconstructs the complete Step 9A whole-book format")
    func markdownInterchange() async throws {
        let fixture = try await makeFixture()
        let book = try #require(try await fixture.repository.fetchLibraryBooks().first)
        let file = try await MarkdownInterchangeService(repository: fixture.repository)
            .exportMarkdown(book: book)
        let source = try #require(String(data: file.data, encoding: .utf8))
        let reparsed = try BookContentParser().parseCompleteBook(source)
        let chapters = try await fixture.repository.chapters(forBookID: book.id)

        #expect(file.suggestedFilename == "Portable Book.md")
        #expect(source.hasPrefix("# Portable Book\n\n### Author: First Author\n\n### Author: 第二作者"))
        #expect(reparsed.title == book.title)
        #expect(reparsed.authors == book.authors)
        #expect(reparsed.chapters.map(\.title) == chapters.map(\.title))
        #expect(reparsed.chapters.map(\.markdown) == chapters.map(\.markdown))

        try await fixture.database.close()
        try? FileManager.default.removeItem(at: fixture.containerURL)
    }

    private func makeFixture() async throws -> InterchangeFixture {
        let container = FileManager.default.temporaryDirectory.appending(
            path: "iEvelyn-InterchangeTests-\(UUID().databaseString)",
            directoryHint: .isDirectory
        )
        let root = container.appending(path: "iEvelyn", directoryHint: .isDirectory)
        let database = try LibraryDatabase.makeTemporary(in: root)
        let repository = GRDBLibraryRepository(database: database)
        try await repository.prepareAssetStorage()

        let coverData = try #require(Data(base64Encoded: Self.onePixelPNG))
        let coverURL = container.appending(path: "cover.png", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try coverData.write(to: coverURL)
        let createdAt = Date(timeIntervalSince1970: 1_723_776_000)
        let bookID = try await repository.createBook(
            metadata: BookMetadataInput(
                title: "Portable Book",
                subtitle: "A complete snapshot",
                authors: ["First Author", "第二作者"],
                tags: ["Backup", "离线"],
                summary: "Canonical summary"
            ),
            contentChapters: [
                ImportedBookChapter(title: "Opening", markdown: "## Opening\n\nFirst paragraph."),
                ImportedBookChapter(title: "结尾", markdown: "## 结尾\n\n最后一段。"),
            ],
            coverSourceURL: coverURL,
            at: createdAt
        )
        let chapters = try await repository.chapters(forBookID: bookID)
        let secondChapter = try #require(chapters.last)
        try await repository.saveReadingProgress(
            ReadingProgress(
                bookID: bookID,
                chapterID: secondChapter.id,
                stableBlockID: "paragraph-end",
                textQuote: "最后一段。",
                contextBefore: nil,
                contextAfter: nil,
                fractionInChapter: 0.75,
                overallProgress: 0.9,
                lastReadAt: createdAt.addingTimeInterval(60)
            )
        )
        try await repository.createBookmark(
            Bookmark(
                bookID: bookID,
                chapterID: secondChapter.id,
                stableBlockID: "paragraph-end",
                textQuote: "最后一段。",
                fractionInChapter: 0.75,
                createdAt: createdAt.addingTimeInterval(90),
                updatedAt: createdAt.addingTimeInterval(90)
            )
        )
        return InterchangeFixture(
            containerURL: container,
            libraryRootURL: root,
            database: database,
            repository: repository,
            coverData: coverData
        )
    }

    private func makeService(repository: GRDBLibraryRepository) -> LibraryInterchangeService {
        LibraryInterchangeService(
            repository: repository,
            now: { Date(timeIntervalSince1970: 1_786_874_722.125) },
            appVersion: "1.0-test",
            appBuild: "13"
        )
    }

    private func snapshot(_ database: LibraryDatabase) async throws -> CanonicalLibrarySnapshot {
        try await database.read { database in
            CanonicalLibrarySnapshot(
                books: try Book.fetchAll(database, sql: "SELECT * FROM books ORDER BY id"),
                authors: try Author.fetchAll(database, sql: "SELECT * FROM authors ORDER BY id"),
                bookAuthors: try BookAuthor.fetchAll(
                    database,
                    sql: "SELECT * FROM bookAuthors ORDER BY bookID, position, authorID"
                ),
                chapters: try Chapter.fetchAll(
                    database,
                    sql: "SELECT * FROM chapters ORDER BY bookID, position, id"
                ),
                assets: try Asset.fetchAll(database, sql: "SELECT * FROM assets ORDER BY id"),
                tags: try iEvelyn.Tag.fetchAll(database, sql: "SELECT * FROM tags ORDER BY id"),
                bookTags: try BookTag.fetchAll(
                    database,
                    sql: "SELECT * FROM bookTags ORDER BY bookID, tagID"
                ),
                readingProgress: try ReadingProgress.fetchAll(
                    database,
                    sql: "SELECT * FROM readingProgress ORDER BY bookID"
                ),
                bookmarks: try Bookmark.fetchAll(database, sql: "SELECT * FROM bookmarks ORDER BY id")
            )
        }
    }

    private func archiveFiles(_ data: Data) throws -> [String: Data] {
        let archive = try Archive(data: data, accessMode: .read)
        return try Dictionary(uniqueKeysWithValues: archive.map { entry in
            (entry.path, try archiveData(at: entry.path, in: archive))
        })
    }

    private func decodedManifest(from files: [String: Data]) throws -> LibraryBundleManifest {
        try JSONDecoder().decode(
            LibraryBundleManifest.self,
            from: #require(files[LibraryBundleManifest.manifestPath])
        )
    }

    private func archiveData(at path: String, in archive: Archive) throws -> Data {
        let entry = try #require(archive[path])
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        return data
    }

    private func makeArchive(files: [String: Data]) throws -> Data {
        let archive = try Archive(accessMode: .create)
        for path in files.keys.sorted() {
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

    private func restoreDirectories(beside root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: root.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasPrefix(".iEvelyn-restore-") }
    }

    private static let onePixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}

nonisolated private struct InterchangeFixture: Sendable {
    let containerURL: URL
    let libraryRootURL: URL
    let database: LibraryDatabase
    let repository: GRDBLibraryRepository
    let coverData: Data
}

nonisolated private struct CanonicalLibrarySnapshot: Equatable, Sendable {
    let books: [Book]
    let authors: [Author]
    let bookAuthors: [BookAuthor]
    let chapters: [Chapter]
    let assets: [Asset]
    let tags: [iEvelyn.Tag]
    let bookTags: [BookTag]
    let readingProgress: [ReadingProgress]
    let bookmarks: [Bookmark]
}
