import CryptoKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

nonisolated struct EPUBExportFile: Equatable, Sendable {
    let data: Data
    let suggestedFilename: String
}

nonisolated enum EPUBExportError: LocalizedError, Equatable, Sendable {
    case trashedBook
    case missingTitle
    case missingAuthor
    case missingChapters
    case renderingIssue(chapterTitle: String, messages: [String])
    case malformedDocument(path: String)
    case missingAsset(UUID)
    case unsupportedAsset(UUID, mediaType: String)
    case corruptAsset(UUID)
    case assetConversionFailed(UUID)
    case archiveCreationFailed

    var errorDescription: String? {
        switch self {
        case .trashedBook:
            "Restore this book before exporting it."
        case .missingTitle:
            "Add a book title before exporting."
        case .missingAuthor:
            "Add at least one author before exporting."
        case .missingChapters:
            "This book has no chapters to export."
        case .renderingIssue(let chapterTitle, let messages):
            "“\(chapterTitle)” could not be exported safely. \(messages.joined(separator: " "))"
        case .malformedDocument(let path):
            "The generated EPUB document at \(path) is not well-formed XML."
        case .missingAsset:
            "A referenced book image is missing. Replace or remove the image before exporting."
        case .unsupportedAsset(_, let mediaType):
            "A referenced book image uses the unsupported EPUB media type “\(mediaType)”. Replace it with JPEG, PNG, GIF, HEIC, or HEIF."
        case .corruptAsset:
            "A referenced book image no longer matches its stored checksum. Replace the image before exporting."
        case .assetConversionFailed:
            "A referenced HEIC or HEIF image could not be converted to EPUB-compatible PNG. Replace the image before exporting."
        case .archiveCreationFailed:
            "The EPUB archive could not be created. No file was exported."
        }
    }
}

nonisolated protocol EPUBExporting: Sendable {
    func export(book: LibraryBook) async throws -> EPUBExportFile
}

actor EPUBExportService: EPUBExporting {
    static let exportLanguage = "und"

    private let repository: any LibraryRepository
    private let renderer: any MarkdownRendering

    init(
        repository: any LibraryRepository,
        renderer: any MarkdownRendering = MarkdownRenderingService()
    ) {
        self.repository = repository
        self.renderer = renderer
    }

    func export(book: LibraryBook) async throws -> EPUBExportFile {
        try Self.validate(book: book)
        try Task.checkCancellation()

        let chapters = try await repository.chapters(forBookID: book.id)
        guard !chapters.isEmpty else {
            throw EPUBExportError.missingChapters
        }
        let storedAssets = try await repository.assets(forBookID: book.id)
        let storedAssetsByID = Dictionary(uniqueKeysWithValues: storedAssets.map { ($0.id, $0) })
        let configurationsByID = Dictionary(
            uniqueKeysWithValues: storedAssets.compactMap { asset in
                EPUBAssetConfiguration(asset: asset).map { (asset.id, $0) }
            }
        )
        let renderAssets = configurationsByID.values.map(\.renderAsset)

        var renderedChapters: [EPUBRenderedChapter] = []
        var referencedAssetIDs = Set<UUID>()
        for chapter in chapters {
            try Task.checkCancellation()
            let result: MarkdownRenderResult
            do {
                result = try await renderer.render(
                    MarkdownRenderRequest(
                        markdown: chapter.markdown,
                        bookID: book.id,
                        assets: renderAssets,
                        mode: .epubXHTML,
                        documentTitle: chapter.title,
                        language: Self.exportLanguage
                    )
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw EPUBExportError.renderingIssue(
                    chapterTitle: chapter.title,
                    messages: [error.localizedDescription]
                )
            }

            guard result.issues.isEmpty else {
                throw EPUBExportError.renderingIssue(
                    chapterTitle: chapter.title,
                    messages: result.issues.map(\.message)
                )
            }
            try EPUBXMLValidator.validate(
                result.document,
                path: EPUBPath.chapter(chapter.id)
            )
            referencedAssetIDs.formUnion(result.referencedAssetIDs)
            renderedChapters.append(
                EPUBRenderedChapter(
                    chapter: chapter,
                    document: result.document
                )
            )
        }

        if let coverAsset = book.coverAsset {
            referencedAssetIDs.insert(coverAsset.id)
        }

        var packagedAssets: [EPUBPackagedAsset] = []
        for assetID in referencedAssetIDs.sorted(by: { $0.databaseString < $1.databaseString }) {
            try Task.checkCancellation()
            guard let asset = storedAssetsByID[assetID] else {
                throw EPUBExportError.missingAsset(assetID)
            }
            guard let configuration = configurationsByID[assetID] else {
                throw EPUBExportError.unsupportedAsset(assetID, mediaType: asset.mediaType)
            }
            packagedAssets.append(
                try await packagedAsset(asset: asset, configuration: configuration)
            )
        }

        let packageEntries = try EPUBPackageBuilder.build(
            book: book,
            chapters: renderedChapters,
            assets: packagedAssets,
            coverAssetID: book.coverAsset?.id,
            language: Self.exportLanguage
        )
        let archiveData = try EPUBArchiveWriter.makeArchive(entries: packageEntries)
        return EPUBExportFile(
            data: archiveData,
            suggestedFilename: EPUBFilename.suggested(for: book.title)
        )
    }

    private func packagedAsset(
        asset: Asset,
        configuration: EPUBAssetConfiguration
    ) async throws -> EPUBPackagedAsset {
        let assetURL: URL
        do {
            assetURL = try BookAssetReference(bookID: asset.bookID, assetID: asset.id).url()
        } catch {
            throw EPUBExportError.missingAsset(asset.id)
        }

        let payload: LibraryAssetPayload
        do {
            payload = try await repository.bookAssetPayload(for: assetURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw EPUBExportError.missingAsset(asset.id)
        }
        guard payload.mediaType.caseInsensitiveCompare(asset.mediaType) == .orderedSame else {
            throw EPUBExportError.corruptAsset(asset.id)
        }
        let checksum = SHA256.hash(data: payload.data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard checksum.caseInsensitiveCompare(asset.checksum) == .orderedSame else {
            throw EPUBExportError.corruptAsset(asset.id)
        }

        let data: Data
        switch configuration.conversion {
        case .none:
            data = payload.data
        case .png:
            guard let converted = EPUBImageConverter.pngData(from: payload.data) else {
                throw EPUBExportError.assetConversionFailed(asset.id)
            }
            data = converted
        }
        return EPUBPackagedAsset(
            asset: asset,
            data: data,
            mediaType: configuration.mediaType,
            fileExtension: configuration.fileExtension
        )
    }

    private static func validate(book: LibraryBook) throws {
        guard !book.isTrashed else {
            throw EPUBExportError.trashedBook
        }
        guard !book.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EPUBExportError.missingTitle
        }
        guard !book.authors.isEmpty,
              book.authors.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw EPUBExportError.missingAuthor
        }
    }
}

struct EPUBExportDocument: FileDocument {
    static let contentType = UTType(filenameExtension: "epub") ?? .data

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

nonisolated struct EPUBExportPresentation: Identifiable, Sendable {
    let id = UUID()
    let file: EPUBExportFile
}

nonisolated enum EPUBFilename {
    static func suggested(for title: String) -> String {
        let replacedScalars = title.unicodeScalars.map { scalar -> Character in
            if scalar == "/" || scalar == ":" || CharacterSet.controlCharacters.contains(scalar) {
                return "-"
            }
            return Character(String(scalar))
        }
        let normalized = String(replacedScalars)
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let basename = normalized.isEmpty ? "Untitled Book" : String(normalized.prefix(120))
        return "\(basename).epub"
    }
}

nonisolated private enum EPUBAssetConversion: Sendable {
    case none
    case png
}

nonisolated private struct EPUBAssetConfiguration: Sendable {
    let renderAsset: Asset
    let mediaType: String
    let fileExtension: String
    let conversion: EPUBAssetConversion

    init?(asset: Asset) {
        let mediaType: String
        let fileExtension: String
        let conversion: EPUBAssetConversion
        switch asset.mediaType.lowercased() {
        case "image/jpeg", "image/jpg":
            mediaType = "image/jpeg"
            fileExtension = "jpg"
            conversion = .none
        case "image/png":
            mediaType = "image/png"
            fileExtension = "png"
            conversion = .none
        case "image/gif":
            mediaType = "image/gif"
            fileExtension = "gif"
            conversion = .none
        case "image/heic", "image/heif":
            mediaType = "image/png"
            fileExtension = "png"
            conversion = .png
        default:
            return nil
        }

        var renderAsset = asset
        renderAsset.mediaType = mediaType
        renderAsset.storageRelativePath = "Assets/\(asset.id.databaseString).\(fileExtension)"
        self.renderAsset = renderAsset
        self.mediaType = mediaType
        self.fileExtension = fileExtension
        self.conversion = conversion
    }
}

nonisolated private struct EPUBPackagedAsset: Sendable {
    let asset: Asset
    let data: Data
    let mediaType: String
    let fileExtension: String

    var path: String {
        EPUBPath.asset(asset.id, fileExtension: fileExtension)
    }

    var manifestID: String {
        "asset-\(asset.id.databaseString.replacingOccurrences(of: "-", with: ""))"
    }
}

nonisolated private struct EPUBRenderedChapter: Sendable {
    let chapter: Chapter
    let document: String

    var path: String { EPUBPath.chapter(chapter.id) }

    var manifestID: String {
        "chapter-\(chapter.id.databaseString.replacingOccurrences(of: "-", with: ""))"
    }
}

nonisolated struct EPUBArchiveEntry: Equatable, Sendable {
    let path: String
    let data: Data
    let isCompressed: Bool
}

nonisolated private enum EPUBPackageBuilder {
    static func build(
        book: LibraryBook,
        chapters: [EPUBRenderedChapter],
        assets: [EPUBPackagedAsset],
        coverAssetID: UUID?,
        language: String
    ) throws -> [EPUBArchiveEntry] {
        guard !chapters.isEmpty else {
            throw EPUBExportError.missingChapters
        }
        let coverAsset = coverAssetID.flatMap { id in assets.first { $0.asset.id == id } }
        let container = containerDocument
        let navigation = try navigationDocument(
            book: book,
            chapters: chapters,
            language: language
        )
        let cover = coverDocument(
            book: book,
            coverAsset: coverAsset,
            language: language
        )
        let package = packageDocument(
            book: book,
            chapters: chapters,
            assets: assets,
            coverAssetID: coverAssetID,
            language: language
        )

        var xmlDocuments = [
            EPUBPath.container: container,
            EPUBPath.package: package,
            EPUBPath.navigation: navigation,
            EPUBPath.cover: cover,
        ]
        for chapter in chapters {
            xmlDocuments[chapter.path] = chapter.document
        }
        for (path, document) in xmlDocuments {
            try EPUBXMLValidator.validate(document, path: path)
        }

        var entries = [
            EPUBArchiveEntry(
                path: EPUBPath.mimetype,
                data: Data("application/epub+zip".utf8),
                isCompressed: false
            ),
            EPUBArchiveEntry(path: EPUBPath.container, data: Data(container.utf8), isCompressed: true),
            EPUBArchiveEntry(path: EPUBPath.package, data: Data(package.utf8), isCompressed: true),
            EPUBArchiveEntry(path: EPUBPath.navigation, data: Data(navigation.utf8), isCompressed: true),
            EPUBArchiveEntry(
                path: EPUBPath.stylesheet,
                data: Data(epubStylesheet.utf8),
                isCompressed: true
            ),
            EPUBArchiveEntry(path: EPUBPath.cover, data: Data(cover.utf8), isCompressed: true),
        ]
        entries.append(contentsOf: chapters.map {
            EPUBArchiveEntry(path: $0.path, data: Data($0.document.utf8), isCompressed: true)
        })
        entries.append(contentsOf: assets.map {
            EPUBArchiveEntry(path: $0.path, data: $0.data, isCompressed: false)
        })
        return entries
    }

    private static let containerDocument = """
    <?xml version="1.0" encoding="utf-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml" />
      </rootfiles>
    </container>
    """

    private static func packageDocument(
        book: LibraryBook,
        chapters: [EPUBRenderedChapter],
        assets: [EPUBPackagedAsset],
        coverAssetID: UUID?,
        language: String
    ) -> String {
        let creators = book.authors.enumerated().map { offset, author in
            let identifier = "creator-\(offset + 1)"
            return """
                <dc:creator id="\(identifier)">\(xmlEscaped(author))</dc:creator>
                <meta refines="#\(identifier)" property="role" scheme="marc:relators">aut</meta>
            """
        }
        .joined(separator: "\n")
        let subtitle = book.subtitle.map {
            """
                <dc:title id="subtitle">\(xmlEscaped($0))</dc:title>
                <meta refines="#subtitle" property="title-type">subtitle</meta>
            """
        } ?? ""
        let description = book.summary.isEmpty
            ? ""
            : "<dc:description>\(xmlEscaped(book.summary))</dc:description>"
        let assetItems = assets.map { asset in
            let properties = asset.asset.id == coverAssetID ? " properties=\"cover-image\"" : ""
            return "<item id=\"\(asset.manifestID)\" href=\"\(relativeToOEBPS(asset.path))\" media-type=\"\(asset.mediaType)\"\(properties) />"
        }
        .joined(separator: "\n    ")
        let chapterItems = chapters.map { chapter in
            "<item id=\"\(chapter.manifestID)\" href=\"\(relativeToOEBPS(chapter.path))\" media-type=\"application/xhtml+xml\" />"
        }
        .joined(separator: "\n    ")
        let spine = chapters.map { "<itemref idref=\"\($0.manifestID)\" />" }
            .joined(separator: "\n    ")

        return """
        <?xml version="1.0" encoding="utf-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id" xml:lang="\(xmlEscaped(language))">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="book-id">urn:uuid:\(book.id.databaseString)</dc:identifier>
            <dc:title id="title">\(xmlEscaped(book.title))</dc:title>
            <meta refines="#title" property="title-type">main</meta>
        \(subtitle)
        \(creators)
            <dc:language>\(xmlEscaped(language))</dc:language>
            \(description)
            <meta property="dcterms:modified">\(epubModifiedDate(book.updatedAt))</meta>
          </metadata>
          <manifest>
            <item id="navigation" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav" />
            <item id="stylesheet" href="Styles/book.css" media-type="text/css" />
            <item id="cover-page" href="Text/cover.xhtml" media-type="application/xhtml+xml" />
            \(chapterItems)
            \(assetItems)
          </manifest>
          <spine>
            <itemref idref="cover-page" linear="no" />
            \(spine)
          </spine>
        </package>
        """
    }

    private static func navigationDocument(
        book: LibraryBook,
        chapters: [EPUBRenderedChapter],
        language: String
    ) throws -> String {
        guard let firstChapterPath = chapters.first?.path else {
            throw EPUBExportError.missingChapters
        }
        let items = chapters.map { chapter in
            "<li><a href=\"\(relativeToOEBPS(chapter.path))\">\(xmlEscaped(chapter.chapter.title))</a></li>"
        }
        .joined(separator: "\n        ")
        let firstChapter = relativeToOEBPS(firstChapterPath)
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(xmlEscaped(language))" lang="\(xmlEscaped(language))">
        <head>
          <meta charset="utf-8" />
          <title>Contents — \(xmlEscaped(book.title))</title>
          <link rel="stylesheet" type="text/css" href="Styles/book.css" />
        </head>
        <body>
          <nav epub:type="toc" id="toc">
            <h1>Contents</h1>
            <ol>
              \(items)
            </ol>
          </nav>
          <nav epub:type="landmarks" hidden="hidden">
            <h2>Landmarks</h2>
            <ol>
              <li><a epub:type="cover" href="Text/cover.xhtml">Cover</a></li>
              <li><a epub:type="bodymatter" href="\(firstChapter)">Start Reading</a></li>
            </ol>
          </nav>
        </body>
        </html>
        """
    }

    private static func coverDocument(
        book: LibraryBook,
        coverAsset: EPUBPackagedAsset?,
        language: String
    ) -> String {
        let artwork = coverAsset.map {
            "<img class=\"cover-art\" src=\"../Assets/\($0.asset.id.databaseString).\($0.fileExtension)\" alt=\"Cover of \(xmlEscapedAttribute(book.title))\" />"
        } ?? ""
        let authors = book.authors.map(xmlEscaped).joined(separator: ", ")
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(xmlEscaped(language))" lang="\(xmlEscaped(language))">
        <head>
          <meta charset="utf-8" />
          <title>Cover — \(xmlEscaped(book.title))</title>
          <link rel="stylesheet" type="text/css" href="../Styles/book.css" />
        </head>
        <body epub:type="cover">
          <section class="cover-page">
            \(artwork)
            <h1>\(xmlEscaped(book.title))</h1>
            <p class="cover-authors">\(authors)</p>
          </section>
        </body>
        </html>
        """
    }

    private static let epubStylesheet = MarkdownStyles.epub + """

    .cover-page { min-height: 90vh; display: flex; flex-direction: column; justify-content: center; text-align: center; }
    .cover-art { max-height: 75vh; object-fit: contain; }
    .cover-authors { color: #62666d; }
    nav ol { padding-inline-start: 1.5em; }
    """

    private static func relativeToOEBPS(_ path: String) -> String {
        path.hasPrefix("OEBPS/") ? String(path.dropFirst("OEBPS/".count)) : path
    }
}

nonisolated enum EPUBArchiveWriter {
    private static let deterministicDate = Date(timeIntervalSince1970: 315_532_800)

    static func makeArchive(entries: [EPUBArchiveEntry]) throws -> Data {
        guard entries.first?.path == EPUBPath.mimetype,
              entries.first?.isCompressed == false else {
            throw EPUBExportError.archiveCreationFailed
        }
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
                    compressionMethod: entry.isCompressed ? .deflate : .none,
                    provider: { position, size in
                        guard position >= 0,
                              position <= Int64(data.count),
                              let start = Int(exactly: position) else {
                            throw EPUBExportError.archiveCreationFailed
                        }
                        let end = min(data.count, start + size)
                        return data.subdata(in: start..<end)
                    }
                )
            }
            guard let data = archive.data else {
                throw EPUBExportError.archiveCreationFailed
            }
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as EPUBExportError {
            throw error
        } catch {
            throw EPUBExportError.archiveCreationFailed
        }
    }
}

nonisolated private enum EPUBImageConverter {
    static func pngData(from sourceData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return output as Data
    }
}

nonisolated private enum EPUBXMLValidator {
    static func validate(_ document: String, path: String) throws {
        let parser = XMLParser(data: Data(document.utf8))
        let delegate = EPUBXMLValidationDelegate()
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            throw EPUBExportError.malformedDocument(path: path)
        }
    }
}

nonisolated private final class EPUBXMLValidationDelegate: NSObject, XMLParserDelegate {
    func parser(
        _ parser: XMLParser,
        resolveExternalEntityName name: String,
        systemID: String?
    ) -> Data? {
        nil
    }
}

nonisolated private enum EPUBPath {
    static let mimetype = "mimetype"
    static let container = "META-INF/container.xml"
    static let package = "OEBPS/package.opf"
    static let navigation = "OEBPS/nav.xhtml"
    static let stylesheet = "OEBPS/Styles/book.css"
    static let cover = "OEBPS/Text/cover.xhtml"

    static func chapter(_ id: UUID) -> String {
        "OEBPS/Text/chapter-\(id.databaseString).xhtml"
    }

    static func asset(_ id: UUID, fileExtension: String) -> String {
        "OEBPS/Assets/\(id.databaseString).\(fileExtension)"
    }
}

nonisolated private func epubModifiedDate(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
}

nonisolated private func xmlEscaped(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

nonisolated private func xmlEscapedAttribute(_ value: String) -> String {
    xmlEscaped(value)
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}
