import CryptoKit
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

nonisolated enum LibraryAssetError: LocalizedError, Equatable, Sendable {
    case unsupportedImageFormat
    case unreadableImage
    case storageUnavailable
    case fileImportFailed
    case invalidStoragePath
    case storedAssetMissing
    case invalidAssetURL
    case assetReferenceNotFound
    case cleanupIncomplete(completedAction: String, remainingFileCount: Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedImageFormat:
            "Choose a JPEG, PNG, or HEIC image."
        case .unreadableImage:
            "The selected file could not be read as an image. It may be damaged or incomplete."
        case .storageUnavailable:
            "iEvelyn could not prepare its local asset folders. Check available disk space and try again."
        case .fileImportFailed:
            "The cover could not be copied into the library. The original file was not changed."
        case .invalidStoragePath:
            "The library rejected an unsafe asset path."
        case .storedAssetMissing:
            "The stored cover file is missing. Choose the cover again or remove it from the book."
        case .invalidAssetURL:
            "The book asset reference is invalid."
        case .assetReferenceNotFound:
            "The requested book asset no longer exists."
        case .cleanupIncomplete(let completedAction, let remainingFileCount):
            "\(completedAction), but \(remainingFileCount) obsolete asset file(s) could not be removed. The library remains usable and will retry cleanup when it next opens."
        }
    }
}

nonisolated struct BookAssetReference: Equatable, Hashable, Sendable {
    static let scheme = "book-asset"

    let bookID: UUID
    let assetID: UUID

    init(bookID: UUID, assetID: UUID) {
        self.bookID = bookID
        self.assetID = assetID
    }

    init(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == Self.scheme,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil,
              let host = components.host,
              let bookID = UUID(uuidString: host),
              host == bookID.databaseString else {
            throw LibraryAssetError.invalidAssetURL
        }

        let pathComponents = components.percentEncodedPath.split(separator: "/")
        guard pathComponents.count == 1,
              let assetID = UUID(uuidString: String(pathComponents[0])),
              String(pathComponents[0]) == assetID.databaseString else {
            throw LibraryAssetError.invalidAssetURL
        }

        self.bookID = bookID
        self.assetID = assetID
    }

    func url() throws -> URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = bookID.databaseString
        components.path = "/\(assetID.databaseString)"
        guard let url = components.url else {
            throw LibraryAssetError.invalidAssetURL
        }
        return url
    }
}

nonisolated struct AssetStorageAudit: Equatable, Sendable {
    let orphanedRelativePaths: [String]
    let missingReferencedRelativePaths: [String]
}

nonisolated struct AssetStorageRepairReport: Equatable, Sendable {
    let removedOrphanCount: Int
    let failedRemovalCount: Int
    let missingReferencedRelativePaths: [String]
}

nonisolated struct PreparedLibraryAsset: Sendable {
    let asset: Asset
}

nonisolated struct LibraryAssetPayload: Equatable, Sendable {
    let data: Data
    let mediaType: String
}

actor LibraryAssetStore {
    static let assetsDirectoryName = "Assets"
    static let cacheDirectoryName = "Cache"
    static let booksDirectoryName = "Books"
    static let coverCacheDirectoryName = "Covers"
    static let thumbnailMaximumPixelSize = 640
    private static let logger = Logger(subsystem: "org.cysun.iEvelyn", category: "LibraryAssets")

    let libraryRootURL: URL
    private let fileManager: FileManager
    private let removesRootOnDeinit: Bool

    init(
        libraryRootURL: URL,
        fileManager: FileManager = .default,
        removesRootOnDeinit: Bool = false
    ) {
        self.libraryRootURL = libraryRootURL.standardizedFileURL
        self.fileManager = fileManager
        self.removesRootOnDeinit = removesRootOnDeinit
    }

    deinit {
        guard removesRootOnDeinit else { return }
        let cleanupFileManager = FileManager()
        do {
            if cleanupFileManager.fileExists(atPath: libraryRootURL.path) {
                try cleanupFileManager.removeItem(at: libraryRootURL)
            }
        } catch {
            Self.logger.error("Could not remove an ephemeral in-memory asset directory.")
        }
    }

    static func defaultStore(for database: LibraryDatabase) -> LibraryAssetStore {
        if let databaseURL = database.location.databaseURL {
            return LibraryAssetStore(libraryRootURL: databaseURL.deletingLastPathComponent())
        }

        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "iEvelyn-InMemory", directoryHint: .isDirectory)
            .appending(path: UUID().databaseString, directoryHint: .isDirectory)
        return LibraryAssetStore(libraryRootURL: rootURL, removesRootOnDeinit: true)
    }

    func prepareLibraryLayout() throws {
        try createLibraryDirectories()
    }

    func prepareCoverImport(
        bookID: UUID,
        sourceURL: URL,
        at date: Date
    ) throws -> PreparedLibraryAsset {
        try Task.checkCancellation()
        let didAccessSecurityScopedResource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScopedResource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let assetID = UUID()
        let bookDirectoryURL = assetsBooksURL
            .appending(path: bookID.databaseString, directoryHint: .isDirectory)
        let temporaryAssetURL = bookDirectoryURL
            .appending(path: ".\(assetID.databaseString).importing", directoryHint: .notDirectory)

        var finalAssetURL: URL?
        var finalThumbnailURL: URL?
        var completed = false
        defer {
            if !completed {
                removeTemporaryItem(temporaryAssetURL)
                if let finalAssetURL {
                    removeTemporaryItem(finalAssetURL)
                }
                if let finalThumbnailURL {
                    removeTemporaryItem(finalThumbnailURL)
                }
            }
        }

        do {
            try createLibraryDirectories()
            try fileManager.createDirectory(at: bookDirectoryURL, withIntermediateDirectories: true)
            try fileManager.copyItem(at: sourceURL, to: temporaryAssetURL)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LibraryAssetError.fileImportFailed
        }

        let image = try inspectImage(at: temporaryAssetURL)
        let checksum = try checksum(of: temporaryAssetURL)
        let values: URLResourceValues
        do {
            values = try temporaryAssetURL.resourceValues(forKeys: [.fileSizeKey])
        } catch {
            throw LibraryAssetError.fileImportFailed
        }
        guard let byteCount = values.fileSize, byteCount >= 0 else {
            throw LibraryAssetError.fileImportFailed
        }
        try Task.checkCancellation()

        let relativePath = Self.authoritativeRelativePath(
            bookID: bookID,
            assetID: assetID,
            fileExtension: image.fileExtension
        )
        let authoritativeURL = try safeFileURL(forRelativePath: relativePath)
        finalAssetURL = authoritativeURL

        let thumbnailRelativePath = Self.thumbnailRelativePath(
            bookID: bookID,
            assetID: assetID,
            checksum: checksum
        )
        let thumbnailURL = try safeFileURL(forRelativePath: thumbnailRelativePath)
        finalThumbnailURL = thumbnailURL

        let temporaryThumbnailURL = coverCacheURL
            .appending(path: ".\(assetID.databaseString).thumbnailing", directoryHint: .notDirectory)
        defer {
            removeTemporaryItem(temporaryThumbnailURL)
        }

        do {
            try writePNG(image.thumbnail, to: temporaryThumbnailURL)
            try Task.checkCancellation()
            try fileManager.moveItem(at: temporaryAssetURL, to: authoritativeURL)
            try fileManager.moveItem(at: temporaryThumbnailURL, to: thumbnailURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LibraryAssetError.fileImportFailed
        }

        let asset = Asset(
            id: assetID,
            bookID: bookID,
            purpose: .cover,
            mediaType: image.mediaType,
            storageRelativePath: relativePath,
            checksum: checksum,
            byteCount: Int64(byteCount),
            pixelWidth: image.pixelWidth,
            pixelHeight: image.pixelHeight,
            createdAt: date,
            updatedAt: date
        )
        completed = true
        return PreparedLibraryAsset(asset: asset)
    }

    func discardPreparedAsset(_ preparedAsset: PreparedLibraryAsset) -> AssetStorageRepairReport {
        removeFiles(for: [preparedAsset.asset])
    }

    func thumbnailData(for asset: Asset) throws -> Data {
        try Task.checkCancellation()
        guard asset.purpose == .cover else {
            throw LibraryAssetError.assetReferenceNotFound
        }

        let thumbnailURL = try safeFileURL(
            forRelativePath: Self.thumbnailRelativePath(for: asset)
        )
        if !fileManager.fileExists(atPath: thumbnailURL.path) {
            let authoritativeURL = try storedFileURL(for: asset)
            let image = try inspectImage(at: authoritativeURL)
            let temporaryURL = coverCacheURL
                .appending(path: ".\(asset.id.databaseString).thumbnailing", directoryHint: .notDirectory)
            defer {
                removeTemporaryItem(temporaryURL)
            }

            do {
                try fileManager.createDirectory(at: coverCacheURL, withIntermediateDirectories: true)
                try writePNG(image.thumbnail, to: temporaryURL)
                try Task.checkCancellation()
                try fileManager.moveItem(at: temporaryURL, to: thumbnailURL)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as LibraryAssetError {
                throw error
            } catch {
                throw LibraryAssetError.fileImportFailed
            }
        }

        do {
            return try Data(contentsOf: thumbnailURL, options: [.mappedIfSafe])
        } catch {
            throw LibraryAssetError.storedAssetMissing
        }
    }

    func storedFileURL(for asset: Asset) throws -> URL {
        let url = try safeFileURL(forRelativePath: asset.storageRelativePath)
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        } catch {
            throw LibraryAssetError.storedAssetMissing
        }
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw LibraryAssetError.storedAssetMissing
        }
        return url
    }

    func storedData(for asset: Asset) throws -> Data {
        let url = try storedFileURL(for: asset)
        do {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw LibraryAssetError.storedAssetMissing
        }
    }

    func verifyChecksum(of asset: Asset) throws -> Bool {
        let url = try storedFileURL(for: asset)
        return try checksum(of: url) == asset.checksum
    }

    func removeFiles(for assets: [Asset]) -> AssetStorageRepairReport {
        var removedCount = 0
        var failedCount = 0

        for asset in assets {
            for relativePath in [
                asset.storageRelativePath,
                Self.thumbnailRelativePath(for: asset)
            ] {
                do {
                    let url = try safeFileURL(forRelativePath: relativePath)
                    guard fileManager.fileExists(atPath: url.path) else { continue }
                    try fileManager.removeItem(at: url)
                    removedCount += 1
                } catch {
                    failedCount += 1
                }
            }
        }

        removeEmptyAssetDirectories()
        return AssetStorageRepairReport(
            removedOrphanCount: removedCount,
            failedRemovalCount: failedCount,
            missingReferencedRelativePaths: []
        )
    }

    func removeBookStorage(bookID: UUID) -> AssetStorageRepairReport {
        var removedCount = 0
        var failedCount = 0
        let bookDirectoryURL = assetsBooksURL
            .appending(path: bookID.databaseString, directoryHint: .isDirectory)

        if fileManager.fileExists(atPath: bookDirectoryURL.path) {
            do {
                try fileManager.removeItem(at: bookDirectoryURL)
                removedCount += 1
            } catch {
                failedCount += 1
            }
        }

        let cachePrefix = "\(bookID.databaseString)-"
        for url in regularFiles(under: coverCacheURL).filter({ $0.lastPathComponent.hasPrefix(cachePrefix) }) {
            do {
                try fileManager.removeItem(at: url)
                removedCount += 1
            } catch {
                failedCount += 1
            }
        }

        removeEmptyAssetDirectories()
        return AssetStorageRepairReport(
            removedOrphanCount: removedCount,
            failedRemovalCount: failedCount,
            missingReferencedRelativePaths: []
        )
    }

    func audit(referencedAssets: [Asset]) -> AssetStorageAudit {
        let referencedAssetPaths = Set(referencedAssets.map(\.storageRelativePath))
        let referencedThumbnailPaths = Set(referencedAssets.filter { $0.purpose == .cover }.map {
            Self.thumbnailRelativePath(for: $0)
        })
        let referencedPaths = referencedAssetPaths.union(referencedThumbnailPaths)

        let storedFiles = regularFiles(under: assetsURL) + regularFiles(under: coverCacheURL)
        let storedRelativePaths = Set(storedFiles.compactMap(relativePath(for:)))

        return AssetStorageAudit(
            orphanedRelativePaths: storedRelativePaths.subtracting(referencedPaths).sorted(),
            missingReferencedRelativePaths: referencedAssetPaths.subtracting(storedRelativePaths).sorted()
        )
    }

    func repair(referencedAssets: [Asset]) -> AssetStorageRepairReport {
        let audit = audit(referencedAssets: referencedAssets)
        var removedCount = 0
        var failedCount = 0

        for relativePath in audit.orphanedRelativePaths {
            do {
                let url = try safeFileURL(forRelativePath: relativePath)
                try fileManager.removeItem(at: url)
                removedCount += 1
            } catch {
                failedCount += 1
            }
        }

        removeEmptyAssetDirectories()
        return AssetStorageRepairReport(
            removedOrphanCount: removedCount,
            failedRemovalCount: failedCount,
            missingReferencedRelativePaths: audit.missingReferencedRelativePaths
        )
    }

    func thumbnailURL(for asset: Asset) throws -> URL {
        try safeFileURL(forRelativePath: Self.thumbnailRelativePath(for: asset))
    }

    private var assetsURL: URL {
        libraryRootURL.appending(path: Self.assetsDirectoryName, directoryHint: .isDirectory)
    }

    private var assetsBooksURL: URL {
        assetsURL.appending(path: Self.booksDirectoryName, directoryHint: .isDirectory)
    }

    private var coverCacheURL: URL {
        libraryRootURL
            .appending(path: Self.cacheDirectoryName, directoryHint: .isDirectory)
            .appending(path: Self.coverCacheDirectoryName, directoryHint: .isDirectory)
    }

    private func createLibraryDirectories() throws {
        do {
            try fileManager.createDirectory(at: assetsBooksURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: coverCacheURL, withIntermediateDirectories: true)
        } catch {
            throw LibraryAssetError.storageUnavailable
        }
    }

    private func inspectImage(at url: URL) throws -> InspectedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let sourceType = CGImageSourceGetType(source),
              let media = SupportedCoverMedia(typeIdentifier: sourceType as String) else {
            throw LibraryAssetError.unsupportedImageFormat
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              pixelWidth > 0,
              pixelHeight > 0 else {
            throw LibraryAssetError.unreadableImage
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.thumbnailMaximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            throw LibraryAssetError.unreadableImage
        }

        return InspectedImage(
            mediaType: media.mediaType,
            fileExtension: media.fileExtension,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            thumbnail: thumbnail
        )
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw LibraryAssetError.fileImportFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw LibraryAssetError.fileImportFailed
        }
    }

    private func checksum(of url: URL) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw LibraryAssetError.fileImportFailed
        }
        defer {
            do {
                try handle.close()
            } catch {
                Self.logger.error("Could not close a library asset while calculating its checksum.")
            }
        }

        var hasher = SHA256()
        do {
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                try Task.checkCancellation()
                hasher.update(data: data)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LibraryAssetError.fileImportFailed
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func safeFileURL(forRelativePath relativePath: String) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..") else {
            throw LibraryAssetError.invalidStoragePath
        }

        let candidate = libraryRootURL
            .appending(path: relativePath, directoryHint: .notDirectory)
            .standardizedFileURL
        let rootPath = libraryRootURL.path.hasSuffix("/")
            ? libraryRootURL.path
            : "\(libraryRootURL.path)/"
        guard candidate.path.hasPrefix(rootPath) else {
            throw LibraryAssetError.invalidStoragePath
        }
        return candidate
    }

    private func relativePath(for url: URL) -> String? {
        let rootPath = libraryRootURL.path.hasSuffix("/")
            ? libraryRootURL.path
            : "\(libraryRootURL.path)/"
        guard url.standardizedFileURL.path.hasPrefix(rootPath) else { return nil }
        return String(url.standardizedFileURL.path.dropFirst(rootPath.count))
    }

    private func regularFiles(under directoryURL: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [],
            errorHandler: { _, _ in
                Self.logger.error("Could not inspect part of the library asset directory.")
                return true
            }
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL else {
                return nil
            }
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                return values.isRegularFile == true ? url : nil
            } catch {
                Self.logger.error("Could not read library asset file metadata.")
                return nil
            }
        }
    }

    private func removeEmptyAssetDirectories() {
        for root in [assetsBooksURL, coverCacheURL] {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [],
                errorHandler: { _, _ in
                    Self.logger.error("Could not inspect an asset directory while removing empty folders.")
                    return true
                }
            ) else {
                continue
            }
            let directories = enumerator.compactMap { $0 as? URL }.reversed()
            for directory in directories {
                do {
                    let contents = try fileManager.contentsOfDirectory(atPath: directory.path)
                    if contents.isEmpty {
                        try fileManager.removeItem(at: directory)
                    }
                } catch {
                    Self.logger.error("Could not remove an empty library asset directory.")
                }
            }
        }
    }

    private func removeTemporaryItem(_ url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            Self.logger.error("Could not remove a temporary library asset; startup repair will retry cleanup.")
        }
    }

    private static func authoritativeRelativePath(
        bookID: UUID,
        assetID: UUID,
        fileExtension: String
    ) -> String {
        "\(assetsDirectoryName)/\(booksDirectoryName)/\(bookID.databaseString)/\(assetID.databaseString).\(fileExtension)"
    }

    private static func thumbnailRelativePath(for asset: Asset) -> String {
        thumbnailRelativePath(
            bookID: asset.bookID,
            assetID: asset.id,
            checksum: asset.checksum
        )
    }

    private static func thumbnailRelativePath(
        bookID: UUID,
        assetID: UUID,
        checksum: String
    ) -> String {
        "\(cacheDirectoryName)/\(coverCacheDirectoryName)/\(bookID.databaseString)-\(assetID.databaseString)-\(checksum).png"
    }
}

private nonisolated struct InspectedImage {
    let mediaType: String
    let fileExtension: String
    let pixelWidth: Int
    let pixelHeight: Int
    let thumbnail: CGImage
}

private nonisolated struct SupportedCoverMedia {
    let mediaType: String
    let fileExtension: String

    init?(typeIdentifier: String) {
        guard let type = UTType(typeIdentifier) else { return nil }
        if type.conforms(to: .jpeg) {
            mediaType = "image/jpeg"
            fileExtension = "jpg"
        } else if type.conforms(to: .png) {
            mediaType = "image/png"
            fileExtension = "png"
        } else if type.conforms(to: .heic) {
            mediaType = "image/heic"
            fileExtension = "heic"
        } else {
            return nil
        }
    }
}
