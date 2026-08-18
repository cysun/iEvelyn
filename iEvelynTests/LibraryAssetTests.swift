import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import iEvelyn

@Suite("Library assets", .serialized)
struct LibraryAssetTests {
    private let referenceDate = Date(timeIntervalSince1970: 2_100_000_000)

    @Test("Asset storage prepares the documented library layout")
    func preparesLibraryLayout() async throws {
        let environment = try makeEnvironment(named: "layout")
        defer { removeTestDirectory(environment.rootURL) }

        try await environment.repository.prepareAssetStorage()

        var isDirectory: ObjCBool = false
        let booksURL = environment.rootURL.appending(path: "Assets/Books", directoryHint: .isDirectory)
        #expect(FileManager.default.fileExists(atPath: booksURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        isDirectory = false
        let coversURL = environment.rootURL.appending(path: "Cache/Covers", directoryHint: .isDirectory)
        #expect(FileManager.default.fileExists(atPath: coversURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test("JPEG, PNG, and HEIC covers are validated, copied, described, and thumbnailed")
    func supportedCoverImports() async throws {
        let environment = try makeEnvironment(named: "formats")
        defer { removeTestDirectory(environment.rootURL) }

        let formats: [(UTType, String, String)] = [
            (.jpeg, "jpg", "image/jpeg"),
            (.png, "png", "image/png"),
            (.heic, "heic", "image/heic")
        ]

        for (index, format) in formats.enumerated() {
            let bookID = try await environment.repository.createBook(
                metadata: BookMetadataInput(
                    title: "Format \(index)",
                    authors: ["Asset Tester"]
                ),
                at: referenceDate
            )
            let sourceURL = environment.rootURL
                .appending(path: "source-\(index).\(format.1)", directoryHint: .notDirectory)
            try writeImage(to: sourceURL, type: format.0)
            let sourceData = try Data(contentsOf: sourceURL)
            let expectedChecksum = SHA256.hash(data: sourceData)
                .map { String(format: "%02x", $0) }
                .joined()

            try await environment.repository.addCovers(
                bookID: bookID,
                from: [sourceURL],
                at: referenceDate.addingTimeInterval(Double(index + 1))
            )

            let projection = try await environment.repository.fetchLibraryBooks()
            let cover = try #require(projection.first(where: { $0.id == bookID })?.coverAsset)
            #expect(cover.mediaType == format.2)
            #expect(cover.storageRelativePath.hasSuffix(".\(format.1)"))
            #expect(cover.storageRelativePath.contains(bookID.databaseString))
            #expect(cover.checksum == expectedChecksum)
            #expect(cover.byteCount == Int64(sourceData.count))
            #expect(cover.pixelWidth == 48)
            #expect(cover.pixelHeight == 72)
            #expect(try await environment.store.verifyChecksum(of: cover))

            let assetURL = try environment.repository.bookAssetURL(for: cover)
            #expect(assetURL.scheme == BookAssetReference.scheme)
            let storedURL = try await environment.repository.resolveBookAssetURL(assetURL)
            #expect(storedURL != sourceURL)
            #expect(FileManager.default.fileExists(atPath: storedURL.path))

            let thumbnailData = try await environment.repository.coverThumbnailData(for: cover)
            let thumbnailSource = CGImageSourceCreateWithData(thumbnailData as CFData, nil)
            #expect(thumbnailSource != nil)

            try FileManager.default.removeItem(at: sourceURL)
            #expect(FileManager.default.fileExists(atPath: storedURL.path))
            #expect(try await environment.repository.coverThumbnailData(for: cover) == thumbnailData)
        }
    }

    @Test("Multiple covers preserve files, change current selection, and promote deterministically")
    func multipleCoverManagement() async throws {
        let environment = try makeEnvironment(named: "multiple-covers")
        defer { removeTestDirectory(environment.rootURL) }
        let bookID = try await makeBook(in: environment.repository)
        let firstSource = environment.rootURL.appending(path: "first.png")
        let secondSource = environment.rootURL.appending(path: "second.jpg")
        try writeImage(to: firstSource, type: .png)
        try writeImage(to: secondSource, type: .jpeg)

        try await environment.repository.addCovers(
            bookID: bookID,
            from: [firstSource, secondSource],
            at: referenceDate
        )
        let initialCovers = try await environment.repository.coverAssets(forBookID: bookID)
        #expect(initialCovers.count == 2)
        let firstCover = try #require(initialCovers.first(where: { $0.mediaType == "image/png" }))
        let secondCover = try #require(initialCovers.first(where: { $0.mediaType == "image/jpeg" }))
        #expect(firstCover.isCurrentCover)
        #expect(!secondCover.isCurrentCover)
        let firstStoredURL = try await environment.repository.resolveBookAssetURL(
            environment.repository.bookAssetURL(for: firstCover)
        )
        let firstThumbnailURL = try await environment.store.thumbnailURL(for: firstCover)
        let secondStoredURL = try await environment.repository.resolveBookAssetURL(
            environment.repository.bookAssetURL(for: secondCover)
        )
        let secondThumbnailURL = try await environment.store.thumbnailURL(for: secondCover)
        _ = try await environment.repository.coverThumbnailData(for: firstCover)
        _ = try await environment.repository.coverThumbnailData(for: secondCover)
        #expect(FileManager.default.fileExists(atPath: firstStoredURL.path))
        #expect(FileManager.default.fileExists(atPath: secondStoredURL.path))

        try await environment.repository.setCurrentCover(
            bookID: bookID,
            coverID: secondCover.id,
            at: referenceDate.addingTimeInterval(60)
        )
        let selectedBook = try #require(
            try await environment.repository.fetchLibraryBooks().first
        )
        #expect(selectedBook.coverAsset?.id == secondCover.id)
        #expect(selectedBook.coverAssets.count == 2)

        try await environment.repository.removeCover(
            bookID: bookID,
            coverID: secondCover.id,
            at: referenceDate.addingTimeInterval(120)
        )
        let promotedBook = try #require(
            try await environment.repository.fetchLibraryBooks().first
        )
        #expect(promotedBook.coverAsset?.id == firstCover.id)
        #expect(promotedBook.coverAsset?.isCurrentCover == true)
        #expect(FileManager.default.fileExists(atPath: firstStoredURL.path))
        #expect(FileManager.default.fileExists(atPath: firstThumbnailURL.path))
        #expect(!FileManager.default.fileExists(atPath: secondStoredURL.path))
        #expect(!FileManager.default.fileExists(atPath: secondThumbnailURL.path))

        try await environment.repository.removeCover(
            bookID: bookID,
            coverID: firstCover.id,
            at: referenceDate.addingTimeInterval(180)
        )
        #expect(try await environment.repository.fetchLibraryBooks().first?.coverAsset == nil)
        #expect(!FileManager.default.fileExists(atPath: firstStoredURL.path))
        #expect(!FileManager.default.fileExists(atPath: firstThumbnailURL.path))
    }

    @Test("Book metadata and content updates preserve separately managed covers")
    func bookUpdatesPreserveManagedCovers() async throws {
        let environment = try makeEnvironment(named: "unified-book-cover")
        defer { removeTestDirectory(environment.rootURL) }
        let sourceURL = environment.rootURL.appending(path: "cover.png")
        try writeImage(to: sourceURL, type: .png)

        let bookID = try await environment.repository.createBook(
            metadata: BookMetadataInput(title: "Unified Book", authors: ["Asset Tester"]),
            contentChapters: [
                ImportedBookChapter(title: "Opening", markdown: "## Opening\n\nBody.")
            ],
            at: referenceDate
        )
        try await environment.repository.addCovers(
            bookID: bookID,
            from: [sourceURL],
            at: referenceDate
        )
        let createdBook = try #require(
            try await environment.repository.fetchLibraryBooks().first(where: { $0.id == bookID })
        )
        let cover = try #require(createdBook.coverAsset)
        let storedURL = try await environment.repository.resolveBookAssetURL(
            environment.repository.bookAssetURL(for: cover)
        )
        #expect(try await environment.repository.chapters(forBookID: bookID).map(\.title) == ["Opening"])
        #expect(FileManager.default.fileExists(atPath: storedURL.path))

        try await environment.repository.updateBook(
            id: bookID,
            metadata: BookMetadataInput(title: "Updated Unified Book", authors: ["Asset Tester"]),
            chapterUpdate: .unchanged,
            at: referenceDate.addingTimeInterval(60)
        )

        let updatedBook = try #require(
            try await environment.repository.fetchLibraryBooks().first(where: { $0.id == bookID })
        )
        #expect(updatedBook.title == "Updated Unified Book")
        #expect(updatedBook.coverAsset?.id == cover.id)
        #expect(try await environment.repository.chapters(forBookID: bookID).map(\.title) == ["Opening"])
        #expect(FileManager.default.fileExists(atPath: storedURL.path))
    }

    @Test("Unsupported files are rejected without changing the library")
    func unsupportedFileIsRejected() async throws {
        let environment = try makeEnvironment(named: "unsupported")
        defer { removeTestDirectory(environment.rootURL) }
        let bookID = try await makeBook(in: environment.repository)
        let sourceURL = environment.rootURL.appending(path: "not-an-image.txt")
        try Data("plain text".utf8).write(to: sourceURL, options: .atomic)

        do {
            try await environment.repository.addCovers(
                bookID: bookID,
                from: [sourceURL],
                at: referenceDate
            )
            Issue.record("Expected a non-image file to be rejected")
        } catch let error as LibraryAssetError {
            #expect(error == .unsupportedImageFormat)
        }

        #expect(try await environment.repository.fetchAssets().isEmpty)
        let audit = try await environment.repository.auditAssetStorage()
        #expect(audit.orphanedRelativePaths.isEmpty)
    }

    @Test("A failed multi-cover selection rolls back every prepared image")
    func multiCoverPreparationFailureRollsBackAllFiles() async throws {
        let environment = try makeEnvironment(named: "multi-cover-rollback")
        defer { removeTestDirectory(environment.rootURL) }
        let bookID = try await makeBook(in: environment.repository)
        let validURL = environment.rootURL.appending(path: "valid.png")
        let invalidURL = environment.rootURL.appending(path: "invalid.txt")
        try writeImage(to: validURL, type: .png)
        try Data("not an image".utf8).write(to: invalidURL, options: .atomic)

        do {
            try await environment.repository.addCovers(
                bookID: bookID,
                from: [validURL, invalidURL],
                at: referenceDate
            )
            Issue.record("Expected the invalid image to roll back the complete selection")
        } catch let error as LibraryAssetError {
            #expect(error == .unsupportedImageFormat)
        }

        #expect(try await environment.repository.coverAssets(forBookID: bookID).isEmpty)
        let audit = try await environment.repository.auditAssetStorage()
        #expect(audit.orphanedRelativePaths.isEmpty)
    }

    @Test("A database failure rolls back the asset record and copied files")
    func databaseFailureDiscardsPreparedFiles() async throws {
        let environment = try makeEnvironment(named: "atomic-failure")
        defer { removeTestDirectory(environment.rootURL) }
        let sourceURL = environment.rootURL.appending(path: "valid.png")
        try writeImage(to: sourceURL, type: .png)

        do {
            try await environment.repository.addCovers(
                bookID: UUID(),
                from: [sourceURL],
                at: referenceDate
            )
            Issue.record("Expected import for a missing book to fail")
        } catch let error as LibraryRepositoryError {
            #expect(error == .bookNotFound)
        }

        #expect(try await environment.repository.fetchAssets().isEmpty)
        let audit = try await environment.repository.auditAssetStorage()
        #expect(audit.orphanedRelativePaths.isEmpty)
    }

    @Test("Cancelling cover import leaves no database record or copied file")
    func cancelledImportCleansUp() async throws {
        let environment = try makeEnvironment(named: "cancelled")
        defer { removeTestDirectory(environment.rootURL) }
        let bookID = try await makeBook(in: environment.repository)
        let sourceURL = environment.rootURL.appending(path: "valid.png")
        try writeImage(to: sourceURL, type: .png)

        let importTask = Task {
            try await environment.repository.addCovers(
                bookID: bookID,
                from: [sourceURL],
                at: referenceDate
            )
        }
        importTask.cancel()

        do {
            try await importTask.value
            Issue.record("Expected the cancelled import to stop")
        } catch is CancellationError {
            // Expected cancellation is part of the operation contract.
        }

        #expect(try await environment.repository.fetchAssets().isEmpty)
        let audit = try await environment.repository.auditAssetStorage()
        #expect(audit.orphanedRelativePaths.isEmpty)
    }

    @Test("Orphan audit and repair preserve referenced originals and thumbnails")
    func orphanAuditAndRepair() async throws {
        let environment = try makeEnvironment(named: "orphans")
        defer { removeTestDirectory(environment.rootURL) }
        let bookID = try await makeBook(in: environment.repository)
        let sourceURL = environment.rootURL.appending(path: "cover.png")
        try writeImage(to: sourceURL, type: .png)
        try await environment.repository.addCovers(
            bookID: bookID,
            from: [sourceURL],
            at: referenceDate
        )
        let cover = try #require(
            try await environment.repository.fetchLibraryBooks().first?.coverAsset
        )
        let storedURL = try await environment.repository.resolveBookAssetURL(
            environment.repository.bookAssetURL(for: cover)
        )
        let thumbnailURL = try await environment.store.thumbnailURL(for: cover)

        let orphanRelativePath = "Assets/Books/\(bookID.databaseString)/orphan.bin"
        let orphanURL = environment.rootURL.appending(path: orphanRelativePath)
        try Data([0x01, 0x02]).write(to: orphanURL, options: .atomic)

        let audit = try await environment.repository.auditAssetStorage()
        #expect(audit.orphanedRelativePaths == [orphanRelativePath])
        #expect(audit.missingReferencedRelativePaths.isEmpty)

        let report = try await environment.repository.repairAssetStorage()
        #expect(report.removedOrphanCount == 1)
        #expect(report.failedRemovalCount == 0)
        #expect(!FileManager.default.fileExists(atPath: orphanURL.path))
        #expect(FileManager.default.fileExists(atPath: storedURL.path))
        #expect(FileManager.default.fileExists(atPath: thumbnailURL.path))
    }

    @Test("Permanent deletion removes all storage owned by the book")
    func permanentDeletionCleansOwnedStorage() async throws {
        let environment = try makeEnvironment(named: "permanent-delete")
        defer { removeTestDirectory(environment.rootURL) }
        let bookID = try await makeBook(in: environment.repository)
        let sourceURL = environment.rootURL.appending(path: "cover.png")
        try writeImage(to: sourceURL, type: .png)
        try await environment.repository.addCovers(
            bookID: bookID,
            from: [sourceURL],
            at: referenceDate
        )
        let cover = try #require(
            try await environment.repository.fetchLibraryBooks().first?.coverAsset
        )
        let storedURL = try await environment.repository.resolveBookAssetURL(
            environment.repository.bookAssetURL(for: cover)
        )
        let thumbnailURL = try await environment.store.thumbnailURL(for: cover)

        try await environment.repository.moveBookToTrash(
            id: bookID,
            at: referenceDate.addingTimeInterval(60)
        )
        try await environment.repository.deleteBookPermanently(id: bookID)

        #expect(!FileManager.default.fileExists(atPath: storedURL.path))
        #expect(!FileManager.default.fileExists(atPath: thumbnailURL.path))
        #expect(try await environment.repository.fetchAssets().isEmpty)
        let audit = try await environment.repository.auditAssetStorage()
        #expect(audit.orphanedRelativePaths.isEmpty)
    }

    @Test("Empty Trash removes asset storage for every trashed book")
    func emptyTrashCleansAllOwnedStorage() async throws {
        let environment = try makeEnvironment(named: "empty-trash")
        defer { removeTestDirectory(environment.rootURL) }
        var storedURLs: [URL] = []

        for index in 0..<2 {
            let bookID = try await makeBook(in: environment.repository)
            let sourceURL = environment.rootURL.appending(path: "cover-\(index).png")
            try writeImage(to: sourceURL, type: .png)
            try await environment.repository.addCovers(
                bookID: bookID,
                from: [sourceURL],
                at: referenceDate
            )
            let cover = try #require(
                try await environment.repository.fetchLibraryBooks()
                    .first(where: { $0.id == bookID })?.coverAsset
            )
            storedURLs.append(
                try await environment.repository.resolveBookAssetURL(
                    environment.repository.bookAssetURL(for: cover)
                )
            )
            try await environment.repository.moveBookToTrash(
                id: bookID,
                at: referenceDate.addingTimeInterval(60)
            )
        }

        #expect(try await environment.repository.emptyTrash() == 2)
        #expect(storedURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(try await environment.repository.fetchAssets().isEmpty)
        #expect(try await environment.repository.fetchLibraryBooks().isEmpty)
        let audit = try await environment.repository.auditAssetStorage()
        #expect(audit.orphanedRelativePaths.isEmpty)
    }

    @Test("Book asset URLs resolve only known database-backed references")
    func safeBookAssetResolution() async throws {
        let environment = try makeEnvironment(named: "safe-url")
        defer { removeTestDirectory(environment.rootURL) }
        let bookID = try await makeBook(in: environment.repository)
        let sourceURL = environment.rootURL.appending(path: "cover.png")
        try writeImage(to: sourceURL, type: .png)
        let sourceData = try Data(contentsOf: sourceURL)
        try await environment.repository.addCovers(
            bookID: bookID,
            from: [sourceURL],
            at: referenceDate
        )
        let cover = try #require(
            try await environment.repository.fetchLibraryBooks().first?.coverAsset
        )

        let validURL = try environment.repository.bookAssetURL(for: cover)
        let parsedReference = try BookAssetReference(url: validURL)
        #expect(parsedReference == BookAssetReference(bookID: bookID, assetID: cover.id))
        _ = try await environment.repository.resolveBookAssetURL(validURL)
        #expect(try await environment.repository.assets(forBookID: bookID) == [cover])
        #expect(
            try await environment.repository.bookAssetPayload(for: validURL)
                == LibraryAssetPayload(data: sourceData, mediaType: "image/png")
        )

        let unknownURL = try BookAssetReference(bookID: bookID, assetID: UUID()).url()
        do {
            _ = try await environment.repository.resolveBookAssetURL(unknownURL)
            Issue.record("Expected an unknown asset reference to fail")
        } catch let error as LibraryAssetError {
            #expect(error == .assetReferenceNotFound)
        }
        do {
            _ = try await environment.repository.bookAssetPayload(for: unknownURL)
            Issue.record("Expected an unknown asset payload request to fail")
        } catch let error as LibraryAssetError {
            #expect(error == .assetReferenceNotFound)
        }

        let unsafeURL = try #require(URL(string: "book-asset://\(bookID.databaseString)/\(cover.id.databaseString)?path=../../secret"))
        do {
            _ = try BookAssetReference(url: unsafeURL)
            Issue.record("Expected query-bearing asset URL to fail")
        } catch let error as LibraryAssetError {
            #expect(error == .invalidAssetURL)
        }
    }

    private func makeBook(in repository: GRDBLibraryRepository) async throws -> UUID {
        try await repository.createBook(
            metadata: BookMetadataInput(title: "Asset Book", authors: ["Asset Tester"]),
            at: referenceDate
        )
    }

    private func makeEnvironment(named name: String) throws -> AssetTestEnvironment {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "iEvelyn-AssetTests-\(name)-\(UUID().databaseString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let database = try LibraryDatabase.makeTemporary(in: rootURL)
        let store = LibraryAssetStore(libraryRootURL: rootURL)
        let repository = GRDBLibraryRepository(database: database, assetStore: store)
        return AssetTestEnvironment(rootURL: rootURL, store: store, repository: repository)
    }

    private func writeImage(to url: URL, type: UTType) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 48,
            height: 72,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw AssetTestError.couldNotCreateFixture
        }
        context.setFillColor(CGColor(red: 0.16, green: 0.42, blue: 0.68, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 48, height: 72))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                type.identifier as CFString,
                1,
                nil
              ) else {
            throw AssetTestError.couldNotCreateFixture
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AssetTestError.couldNotCreateFixture
        }
    }

    private func removeTestDirectory(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Issue.record("Could not remove temporary asset test directory: \(error.localizedDescription)")
        }
    }
}

private nonisolated struct AssetTestEnvironment: Sendable {
    let rootURL: URL
    let store: LibraryAssetStore
    let repository: GRDBLibraryRepository
}

private nonisolated enum AssetTestError: Error {
    case couldNotCreateFixture
}
