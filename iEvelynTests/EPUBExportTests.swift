import CryptoKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZIPFoundation
@testable import iEvelyn

@Suite("EPUB 3 export", .serialized)
struct EPUBExportTests {
    @Test("One-chapter export has the required EPUB 3 container and package structure")
    func oneChapterStructure() async throws {
        let book = makeBook(title: "One & Only")
        let chapter = makeChapter(
            bookID: book.id,
            title: "Opening",
            markdown: "## Opening\n\nA single safe & sound chapter."
        )
        let exporter = EPUBExportService(
            repository: EPUBFixtureRepository(book: book, chapters: [chapter])
        )

        let file = try await exporter.export(book: book)
        let archive = try Archive(data: file.data, accessMode: .read)
        let entries = Array(archive)
        let paths = entries.map(\.path)

        #expect(file.suggestedFilename == "One & Only.epub")
        #expect(EPUBExportDocument.contentType.preferredFilenameExtension == "epub")
        #expect(paths.first == "mimetype")
        #expect(Array(paths.prefix(6)) == [
            "mimetype",
            "META-INF/container.xml",
            "OEBPS/package.opf",
            "OEBPS/nav.xhtml",
            "OEBPS/Styles/book.css",
            "OEBPS/Text/cover.xhtml",
        ])
        #expect(try data(at: "mimetype", in: archive) == Data("application/epub+zip".utf8))
        #expect(try #require(entries.first).isCompressed == false)
        #expect(try #require(entries.first(where: { $0.path == "OEBPS/package.opf" })).isCompressed)
        #expect(paths.contains("META-INF/container.xml"))
        #expect(paths.contains("OEBPS/package.opf"))
        #expect(paths.contains("OEBPS/nav.xhtml"))
        #expect(paths.contains("OEBPS/Styles/book.css"))
        #expect(paths.contains("OEBPS/Text/cover.xhtml"))
        #expect(paths.contains("OEBPS/Text/chapter-\(chapter.id.databaseString).xhtml"))

        let package = try text(at: "OEBPS/package.opf", in: archive)
        let navigation = try text(at: "OEBPS/nav.xhtml", in: archive)
        let chapterDocument = try text(
            at: "OEBPS/Text/chapter-\(chapter.id.databaseString).xhtml",
            in: archive
        )
        #expect(isWellFormedXML(package))
        #expect(isWellFormedXML(navigation))
        #expect(isWellFormedXML(chapterDocument))
        #expect(package.contains("urn:uuid:\(book.id.databaseString)"))
        #expect(package.contains("<dc:title id=\"title\">One &amp; Only</dc:title>"))
        #expect(package.contains("<dc:language>und</dc:language>"))
        #expect(package.contains("properties=\"nav\""))
        #expect(package.contains("idref=\"chapter-\(compact(chapter.id))\""))
        #expect(navigation.contains("href=\"Text/chapter-\(chapter.id.databaseString).xhtml\""))
        #expect(chapterDocument.contains("href=\"../Styles/book.css\""))
        #expect(!chapterDocument.contains("<style"))
    }

    @Test("Multi-chapter Unicode export uses the current cover and includes only referenced assets")
    func unicodeImageAndManifestCoverage() async throws {
        let bookID = UUID()
        let coverID = UUID()
        let alternateCoverID = UUID()
        let unusedID = UUID()
        let coverData = try #require(Data(base64Encoded: Self.onePixelPNG))
        let alternateCoverData = Data("alternate cover".utf8)
        let unusedData = Data("unused".utf8)
        let cover = makeAsset(
            id: coverID,
            bookID: bookID,
            data: coverData,
            mediaType: "image/png",
            isCurrentCover: true
        )
        let alternateCover = makeAsset(
            id: alternateCoverID,
            bookID: bookID,
            data: alternateCoverData,
            mediaType: "image/png"
        )
        let unused = makeAsset(
            id: unusedID,
            bookID: bookID,
            data: unusedData,
            mediaType: "image/png"
        )
        let book = makeBook(
            id: bookID,
            title: "毫末生 & Friends",
            authors: ["蛋伤", "Zoë Writer"],
            subtitle: "章节一览",
            coverAssets: [alternateCover, cover]
        )
        let assetURL = try BookAssetReference(bookID: bookID, assetID: coverID).url().absoluteString
        let first = makeChapter(
            bookID: bookID,
            title: "开篇",
            markdown: "## 开篇\n\n![封面](\(assetURL))\n\n你好，世界。",
            position: 0
        )
        let second = makeChapter(
            bookID: bookID,
            title: "Café",
            markdown: "## Café\n\nSecond chapter — 👩🏽‍💻",
            position: 1
        )
        let repository = EPUBFixtureRepository(
            book: book,
            chapters: [first, second],
            assets: [cover, alternateCover, unused],
            payloads: [
                coverID: LibraryAssetPayload(data: coverData, mediaType: "image/png"),
                alternateCoverID: LibraryAssetPayload(
                    data: alternateCoverData,
                    mediaType: "image/png"
                ),
                unusedID: LibraryAssetPayload(data: unusedData, mediaType: "image/png"),
            ]
        )
        let exporter = EPUBExportService(repository: repository)

        let file = try await exporter.export(book: book)
        let archive = try Archive(data: file.data, accessMode: .read)
        let entries = Array(archive)
        let paths = entries.map(\.path)
        let coverPath = "OEBPS/Assets/\(coverID.databaseString).png"
        let alternateCoverPath = "OEBPS/Assets/\(alternateCoverID.databaseString).png"
        let unusedPath = "OEBPS/Assets/\(unusedID.databaseString).png"
        let package = try text(at: "OEBPS/package.opf", in: archive)
        let coverDocument = try text(at: "OEBPS/Text/cover.xhtml", in: archive)
        let firstDocument = try text(at: "OEBPS/Text/chapter-\(first.id.databaseString).xhtml", in: archive)

        #expect(paths.contains(coverPath))
        #expect(!paths.contains(alternateCoverPath))
        #expect(!paths.contains(unusedPath))
        #expect(try data(at: coverPath, in: archive) == coverData)
        #expect(try #require(entries.first(where: { $0.path == coverPath })).isCompressed == false)
        #expect(package.contains("media-type=\"image/png\" properties=\"cover-image\""))
        #expect(package.contains("<dc:creator id=\"creator-1\">蛋伤</dc:creator>"))
        #expect(package.contains("<dc:title id=\"subtitle\">章节一览</dc:title>"))
        #expect(coverDocument.contains("src=\"../Assets/\(coverID.databaseString).png\""))
        #expect(firstDocument.contains("src=\"../Assets/\(coverID.databaseString).png\""))
        let firstSpineRange = try #require(
            package.range(of: "idref=\"chapter-\(compact(first.id))\"")
        )
        let secondSpineRange = try #require(
            package.range(of: "idref=\"chapter-\(compact(second.id))\"")
        )
        #expect(firstSpineRange.lowerBound < secondSpineRange.lowerBound)
        try assertManifestAndSpineConsistency(package: package, archivePaths: Set(paths))
    }

    @Test("HEIC cover artwork is converted to EPUB-compatible PNG")
    func heicCoverConversion() async throws {
        let bookID = UUID()
        let coverID = UUID()
        let heicData = try makeHEICData()
        let cover = makeAsset(
            id: coverID,
            bookID: bookID,
            data: heicData,
            mediaType: "image/heic"
        )
        let book = makeBook(
            id: bookID,
            title: "HEIC Cover",
            coverAsset: cover
        )
        let repository = EPUBFixtureRepository(
            book: book,
            chapters: [unsafeWithoutIssue(bookID: bookID)],
            assets: [cover],
            payloads: [
                coverID: LibraryAssetPayload(data: heicData, mediaType: "image/heic")
            ]
        )

        let file = try await EPUBExportService(repository: repository).export(book: book)
        let archive = try Archive(data: file.data, accessMode: .read)
        let pngPath = "OEBPS/Assets/\(coverID.databaseString).png"
        let convertedData = try data(at: pngPath, in: archive)
        let package = try text(at: "OEBPS/package.opf", in: archive)

        #expect(convertedData.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(convertedData != heicData)
        #expect(package.contains("href=\"Assets/\(coverID.databaseString).png\""))
        #expect(package.contains("media-type=\"image/png\" properties=\"cover-image\""))
        #expect(archive["OEBPS/Assets/\(coverID.databaseString).heic"] == nil)
    }

    @Test("Repeated export is byte deterministic and content edits change the result")
    func deterministicReexport() async throws {
        let book = makeBook(title: "Deterministic")
        let original = makeChapter(
            bookID: book.id,
            title: "Chapter",
            markdown: "## Chapter\n\nOriginal text."
        )
        let exporter = EPUBExportService(
            repository: EPUBFixtureRepository(book: book, chapters: [original])
        )

        let first = try await exporter.export(book: book)
        let second = try await exporter.export(book: book)
        #expect(first.data == second.data)

        let edited = makeChapter(
            id: original.id,
            bookID: book.id,
            title: original.title,
            markdown: "## Chapter\n\nEdited text.",
            position: original.position
        )
        let editedExporter = EPUBExportService(
            repository: EPUBFixtureRepository(book: book, chapters: [edited])
        )
        let changed = try await editedExporter.export(book: book)
        #expect(changed.data != first.data)
    }

    @Test("Invalid books and misleading rendered output fail before an archive is offered")
    func preflightFailures() async throws {
        let book = makeBook(title: "Invalid")

        let authorless = makeBook(title: "No Author", authors: [])
        await #expect(throws: EPUBExportError.missingAuthor) {
            try await EPUBExportService(
                repository: EPUBFixtureRepository(book: authorless, chapters: [])
            )
            .export(book: authorless)
        }

        await #expect(throws: EPUBExportError.missingChapters) {
            try await EPUBExportService(
                repository: EPUBFixtureRepository(book: book, chapters: [])
            )
            .export(book: book)
        }

        let unsafe = makeChapter(
            bookID: book.id,
            title: "Unsafe",
            markdown: "## Unsafe\n\n<script>unsafe()</script>"
        )
        do {
            _ = try await EPUBExportService(
                repository: EPUBFixtureRepository(book: book, chapters: [unsafe])
            )
            .export(book: book)
            Issue.record("Expected raw HTML to stop export preflight")
        } catch let error as EPUBExportError {
            guard case .renderingIssue(let title, let messages) = error else {
                Issue.record("Unexpected export error: \(error)")
                return
            }
            #expect(title == "Unsafe")
            #expect(messages.contains(MarkdownRenderIssue.rawHTMLRenderedAsText.message))
        }

        let corruptData = try #require(Data(base64Encoded: Self.onePixelPNG))
        let corrupt = Asset(
            id: UUID(),
            bookID: book.id,
            purpose: .cover,
            mediaType: "image/png",
            storageRelativePath: "Assets/corrupt.png",
            checksum: String(repeating: "0", count: 64),
            byteCount: Int64(corruptData.count)
        )
        let corruptBook = makeBook(
            id: book.id,
            title: book.title,
            authors: book.authors,
            coverAsset: corrupt
        )
        await #expect(throws: EPUBExportError.corruptAsset(corrupt.id)) {
            try await EPUBExportService(
                repository: EPUBFixtureRepository(
                    book: corruptBook,
                    chapters: [unsafeWithoutIssue(bookID: book.id)],
                    assets: [corrupt],
                    payloads: [
                        corrupt.id: LibraryAssetPayload(data: corruptData, mediaType: "image/png")
                    ]
                )
            )
            .export(book: corruptBook)
        }

        let unsupportedData = Data("TIFF".utf8)
        let unsupported = makeAsset(
            id: UUID(),
            bookID: book.id,
            data: unsupportedData,
            mediaType: "image/tiff"
        )
        let unsupportedBook = makeBook(
            id: book.id,
            title: book.title,
            authors: book.authors,
            coverAsset: unsupported
        )
        await #expect(
            throws: EPUBExportError.unsupportedAsset(
                unsupported.id,
                mediaType: "image/tiff"
            )
        ) {
            try await EPUBExportService(
                repository: EPUBFixtureRepository(
                    book: unsupportedBook,
                    chapters: [unsafeWithoutIssue(bookID: book.id)],
                    assets: [unsupported]
                )
            )
            .export(book: unsupportedBook)
        }
    }

    @Test("Cancellation does not publish a partial EPUB")
    func cancellation() async {
        let book = makeBook(title: "Cancelled")
        let chapter = unsafeWithoutIssue(bookID: book.id)
        let exporter = EPUBExportService(
            repository: EPUBFixtureRepository(book: book, chapters: [chapter])
        )
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await exporter.export(book: book)
        }

        do {
            _ = try await task.value
            Issue.record("Expected export cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }
    }

    @Test("Export preflight failures are surfaced as actionable library alerts")
    @MainActor
    func viewModelReportsPreflightFailure() async {
        let book = makeBook(title: "Alerted Export")
        let repository = EPUBFixtureRepository(book: book, chapters: [])
        let model = LibraryViewModel(
            repository: repository,
            initialBooks: [book],
            epubExporter: FailingEPUBExporter(error: .missingChapters)
        )

        let presentation = await model.prepareEPUBExport(for: book)

        #expect(presentation?.file.data == nil)
        #expect(model.alert?.title == "Could Not Export EPUB")
        #expect(model.alert?.message == EPUBExportError.missingChapters.localizedDescription)
        #expect(!model.isPreparingEPUB)
    }

    @Test("Batch export preserves selection order, rejects partial preflight, and uniquifies names")
    @MainActor
    func batchExportPreparation() async {
        let first = makeBook(title: "Shared Title")
        let second = makeBook(title: "Shared Title")
        let books = [first, second]
        let repository = EPUBFixtureRepository(book: first, chapters: [])
        let model = LibraryViewModel(
            repository: repository,
            initialBooks: books,
            epubExporter: BatchEPUBExporter()
        )

        let presentations = await model.prepareEPUBExports(for: books)
        #expect(presentations?.map(\.file.data) == [Data(first.title.utf8), Data(second.title.utf8)])
        #expect(
            BookBatchFilename.uniqued(["Shared Title.epub", "shared title.epub"])
                == ["Shared Title.epub", "shared title 2.epub"]
        )

        let failingModel = LibraryViewModel(
            repository: repository,
            initialBooks: books,
            epubExporter: BatchEPUBExporter(failingBookID: second.id)
        )
        let failedPresentations = await failingModel.prepareEPUBExports(for: books)
        #expect(failedPresentations?.count == nil)
        #expect(failingModel.alert?.title == "Could Not Export Shared Title as EPUB")
        #expect(failingModel.alert?.message.hasPrefix("No files were exported.") == true)
        #expect(!failingModel.isPreparingEPUB)
    }

    private func makeBook(
        id: UUID = UUID(),
        title: String,
        authors: [String] = ["Test Author"],
        subtitle: String? = nil,
        coverAsset: Asset? = nil,
        coverAssets: [Asset] = []
    ) -> LibraryBook {
        LibraryBook(
            id: id,
            title: title,
            subtitle: subtitle,
            authors: authors,
            summary: "Export summary.",
            tags: ["Export"],
            dateAdded: Date(timeIntervalSince1970: 1_700_000_000),
            isFavorite: false,
            isCurrentlyReading: false,
            readingProgress: nil,
            isTrashed: false,
            coverAsset: coverAsset,
            coverAssets: coverAssets,
            coverStyle: .ocean,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_123)
        )
    }

    private func makeChapter(
        id: UUID = UUID(),
        bookID: UUID,
        title: String,
        markdown: String,
        position: Int = 0
    ) -> Chapter {
        Chapter(
            id: id,
            bookID: bookID,
            title: title,
            markdown: markdown,
            position: position,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_123)
        )
    }

    private func unsafeWithoutIssue(bookID: UUID) -> Chapter {
        makeChapter(
            bookID: bookID,
            title: "Chapter",
            markdown: "## Chapter\n\nValid content."
        )
    }

    private func makeAsset(
        id: UUID,
        bookID: UUID,
        data: Data,
        mediaType: String,
        isCurrentCover: Bool = false
    ) -> Asset {
        let checksum = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return Asset(
            id: id,
            bookID: bookID,
            purpose: .cover,
            mediaType: mediaType,
            storageRelativePath: "Assets/\(id.databaseString).\(mediaType == "image/heic" ? "heic" : "png")",
            checksum: checksum,
            byteCount: Int64(data.count),
            isCurrentCover: isCurrentCover
        )
    }

    private func makeHEICData() throws -> Data {
        let pngData = try #require(Data(base64Encoded: Self.onePixelPNG))
        let source = try #require(CGImageSourceCreateWithData(pngData as CFData, nil))
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(
                output,
                UTType.heic.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImageFromSource(destination, source, 0, nil)
        try #require(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func data(at path: String, in archive: Archive) throws -> Data {
        let entry = try #require(archive[path])
        var result = Data()
        _ = try archive.extract(entry) { result.append($0) }
        return result
    }

    private func text(at path: String, in archive: Archive) throws -> String {
        try #require(String(data: data(at: path, in: archive), encoding: .utf8))
    }

    private func isWellFormedXML(_ text: String) -> Bool {
        let parser = XMLParser(data: Data(text.utf8))
        parser.shouldResolveExternalEntities = false
        return parser.parse()
    }

    private func compact(_ id: UUID) -> String {
        id.databaseString.replacingOccurrences(of: "-", with: "")
    }

    private func assertManifestAndSpineConsistency(
        package: String,
        archivePaths: Set<String>
    ) throws {
        let delegate = EPUBPackageInspectionDelegate()
        let parser = XMLParser(data: Data(package.utf8))
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        #expect(parser.parse())
        #expect(Set(delegate.spineIDs).isSubset(of: Set(delegate.manifestByID.keys)))
        for href in delegate.manifestByID.values {
            #expect(archivePaths.contains("OEBPS/\(href)"))
        }
    }

    private static let onePixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}

nonisolated private struct EPUBFixtureRepository: LibraryRepository, Sendable {
    let book: LibraryBook
    let storedChapters: [Chapter]
    let storedAssets: [Asset]
    let payloads: [UUID: LibraryAssetPayload]

    init(
        book: LibraryBook,
        chapters: [Chapter],
        assets: [Asset] = [],
        payloads: [UUID: LibraryAssetPayload] = [:]
    ) {
        self.book = book
        storedChapters = chapters
        storedAssets = assets
        self.payloads = payloads
    }

    func observeLibraryBooks() -> AsyncThrowingStream<[LibraryBook], Error> {
        AsyncThrowingStream { continuation in
            continuation.yield([book])
            continuation.finish()
        }
    }

    func chapters(forBookID bookID: UUID) async throws -> [Chapter] {
        storedChapters.filter { $0.bookID == bookID }.sorted { $0.position < $1.position }
    }

    func assets(forBookID bookID: UUID) async throws -> [Asset] {
        storedAssets.filter { $0.bookID == bookID }
    }

    func bookAssetPayload(for url: URL) async throws -> LibraryAssetPayload {
        let reference = try BookAssetReference(url: url)
        guard let payload = payloads[reference.assetID] else {
            throw LibraryAssetError.storedAssetMissing
        }
        return payload
    }
}

nonisolated private struct FailingEPUBExporter: EPUBExporting, Sendable {
    let error: EPUBExportError

    func export(book: LibraryBook) async throws -> EPUBExportFile {
        throw error
    }
}

nonisolated private struct BatchEPUBExporter: EPUBExporting, Sendable {
    var failingBookID: UUID?

    init(failingBookID: UUID? = nil) {
        self.failingBookID = failingBookID
    }

    func export(book: LibraryBook) async throws -> EPUBExportFile {
        if book.id == failingBookID {
            throw EPUBExportError.missingChapters
        }
        return EPUBExportFile(
            data: Data(book.title.utf8),
            suggestedFilename: EPUBFilename.suggested(for: book.title)
        )
    }
}

nonisolated private final class EPUBPackageInspectionDelegate: NSObject, XMLParserDelegate {
    private(set) var manifestByID: [String: String] = [:]
    private(set) var spineIDs: [String] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "item":
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifestByID[id] = href
            }
        case "itemref":
            if let idref = attributeDict["idref"] {
                spineIDs.append(idref)
            }
        default:
            break
        }
    }
}
