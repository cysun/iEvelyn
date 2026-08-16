import Foundation
import Testing
@testable import iEvelyn

@Suite("Markdown rendering", .serialized)
struct MarkdownRenderingTests {
    private let bookID = UUID(uuid: (
        0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11,
        0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11
    ))

    @Test("GFM fixture renders semantic, escaped, accessible reader HTML")
    func comprehensiveReaderFixture() async throws {
        let renderer = MarkdownRenderingService()
        let markdown = try fixture(named: "comprehensive.md")
        let result = try await renderer.render(
            MarkdownRenderRequest(
                markdown: markdown,
                bookID: bookID,
                mode: .readerHTML,
                documentTitle: "Comprehensive & Safe"
            )
        )

        #expect(result.document.hasPrefix("<!doctype html>"))
        #expect(result.document.contains("Content-Security-Policy"))
        #expect(result.document.contains("<title>Comprehensive &amp; Safe</title>"))
        #expect(result.document.contains(">Chapter &amp; Safety</h1>"))
        #expect(result.document.contains("<em>emphasis</em>"))
        #expect(result.document.contains("<strong>strong text</strong>"))
        #expect(result.document.contains("<del>deleted text</del>"))
        #expect(result.document.contains("<code>inline &lt;code&gt;</code>"))
        #expect(result.document.contains("href=\"https://example.com/read?q=swift&amp;lang=en\""))
        #expect(!result.document.contains("href=\"javascript:"))
        #expect(result.issues.contains(.unsafeLinkOmitted))
        #expect(result.document.contains("<blockquote id="))
        #expect(result.document.contains("<ol id="))
        #expect(result.document.contains("<ul id="))
        #expect(result.document.contains("class=\"task-list-item\""))
        #expect(result.document.contains("checked=\"checked\""))
        #expect(result.document.contains("class=\"table-scroll\""))
        #expect(result.document.contains("class=\"align-right\""))
        #expect(result.document.contains("class=\"language-swift\""))
        #expect(result.document.contains("&lt;safe&gt; &amp; stable"))
        #expect(result.document.contains("章节, café, naïve, and 👩🏽‍💻"))
        #expect(result.document.contains("Footnotes are deliberately literal"))
        #expect(Set(result.blockIDs).count == result.blockIDs.count)
        #expect(result.blockIDs.count >= 12)
        #expect(result.blocks.map(\.id) == result.blockIDs)
        #expect(result.blocks.contains { $0.normalizedText.contains("章节, café, naïve") })
    }

    @Test("Raw HTML, unsafe URLs, remote images, and malformed input fail safely")
    func unsafeAndMalformedFixture() async throws {
        let renderer = MarkdownRenderingService()
        let result = try await renderer.render(
            MarkdownRenderRequest(
                markdown: try fixture(named: "unsafe-and-malformed.md"),
                bookID: bookID,
                mode: .readerHTML
            )
        )

        #expect(result.document.contains("&lt;script&gt;globalThis.compromised = true&lt;/script&gt;"))
        #expect(!result.document.contains("<script>"))
        #expect(!result.document.contains("<img src=\"file:"))
        #expect(result.document.contains("&lt;img src=\"file:"))
        #expect(!result.document.contains("src=\"https:"))
        #expect(!result.document.contains("href=\"file:"))
        #expect(!result.document.contains("href=\"javascript:"))
        #expect(result.document.contains("class=\"unavailable-image\""))
        #expect(result.document.contains("An unclosed code fence remains harmless."))
        #expect(result.issues.contains(.rawHTMLRenderedAsText))
        #expect(result.issues.contains(.unavailableImage))
        #expect(result.issues.contains(.unsafeLinkOmitted))
    }

    @Test("Reader and EPUB outputs use different safe asset and document rules")
    func readerAndEPUBModes() async throws {
        let assetID = UUID(uuid: (
            0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22,
            0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22
        ))
        let asset = makeAsset(id: assetID, bookID: bookID, checksum: "known")
        let reference = try BookAssetReference(bookID: bookID, assetID: assetID).url().absoluteString
        let unknownReference = try BookAssetReference(bookID: bookID, assetID: UUID()).url().absoluteString
        let markdown = """
        # Images

        ![Known image](\(reference) "Known")

        ![Unknown image](\(unknownReference))

        Line one.\\
        Line two.

        ---
        """
        let renderer = MarkdownRenderingService()

        let reader = try await renderer.render(
            MarkdownRenderRequest(
                markdown: markdown,
                bookID: bookID,
                assets: [asset],
                mode: .readerHTML
            )
        )
        let epub = try await renderer.render(
            MarkdownRenderRequest(
                markdown: markdown,
                bookID: bookID,
                assets: [asset],
                mode: .epubXHTML
            )
        )

        #expect(reader.document.contains("src=\"book-asset://11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222\""))
        #expect(reader.document.contains("<br>"))
        #expect(reader.document.contains("<hr id="))
        #expect(reader.document.contains("Content-Security-Policy"))
        #expect(epub.document.hasPrefix("<?xml version=\"1.0\" encoding=\"utf-8\"?>"))
        #expect(epub.document.contains("xmlns=\"http://www.w3.org/1999/xhtml\""))
        #expect(epub.document.contains("href=\"../Styles/book.css\""))
        #expect(!epub.document.contains("<style"))
        #expect(epub.document.contains("src=\"../Assets/22222222-2222-2222-2222-222222222222.png\""))
        #expect(epub.document.contains("<br />"))
        #expect(epub.document.contains("<hr id=") && epub.document.contains(" />"))
        #expect(!epub.document.contains("Content-Security-Policy"))
        #expect(reader.blockIDs == epub.blockIDs)
        #expect(reader.blocks == epub.blocks)
        #expect(epub.referencedAssetIDs == [assetID])
        #expect(reader.issues == [.unavailableImage])
        #expect(epub.issues == [.unavailableImage])
        #expect(parseXML(epub.document) == nil)
    }

    @Test("Stable block IDs survive unrelated insertions and distinguish duplicates")
    func stableBlockIDs() async throws {
        let renderer = MarkdownRenderingService()
        let original = "Intro paragraph.\n\nStable paragraph.\n"
        let inserted = "New earlier paragraph.\n\n\(original)"
        let duplicated = "Stable paragraph.\n\nStable paragraph.\n"

        let first = try await renderer.render(request(original))
        let second = try await renderer.render(request(inserted))
        let duplicateResult = try await renderer.render(request(duplicated))

        let firstStableID = try #require(blockID(containing: "Stable paragraph.", in: first.document))
        let secondStableID = try #require(blockID(containing: "Stable paragraph.", in: second.document))
        #expect(firstStableID == secondStableID)
        #expect(duplicateResult.blockIDs.count == 2)
        #expect(duplicateResult.blockIDs[1] == "\(duplicateResult.blockIDs[0])-2")
    }

    @Test("Cache invalidates for every input that changes rendered output")
    func cacheInvalidation() async throws {
        let renderer = MarkdownRenderingService(rendererVersion: 7)
        let baseRequest = request("Cached source.")
        let first = try await renderer.render(baseRequest)
        let second = try await renderer.render(baseRequest)
        #expect(first == second)
        #expect(await renderer.uncachedRenderCount == 1)

        _ = try await renderer.render(request("Changed source."))
        #expect(await renderer.uncachedRenderCount == 2)

        _ = try await renderer.render(
            MarkdownRenderRequest(
                markdown: "Cached source.",
                bookID: bookID,
                mode: .epubXHTML
            )
        )
        #expect(await renderer.uncachedRenderCount == 3)

        let asset = makeAsset(id: UUID(), bookID: bookID, checksum: "new-asset")
        _ = try await renderer.render(
            MarkdownRenderRequest(
                markdown: "Cached source.",
                bookID: bookID,
                assets: [asset],
                mode: .readerHTML
            )
        )
        #expect(await renderer.uncachedRenderCount == 4)

        _ = try await renderer.render(
            MarkdownRenderRequest(
                markdown: "Cached source.",
                bookID: bookID,
                mode: .readerHTML,
                documentTitle: "A different title"
            )
        )
        #expect(await renderer.uncachedRenderCount == 5)

        _ = try await renderer.render(
            MarkdownRenderRequest(
                markdown: "Cached source.",
                bookID: bookID,
                mode: .readerHTML,
                language: "zh-Hans"
            )
        )
        #expect(await renderer.uncachedRenderCount == 6)

        let upgradedRenderer = MarkdownRenderingService(rendererVersion: 8)
        let upgraded = try await upgradedRenderer.render(baseRequest)
        #expect(first.cacheKey.rendererVersion == 7)
        #expect(upgraded.cacheKey.rendererVersion == 8)
        #expect(first.cacheKey != upgraded.cacheKey)
        #expect(first.document.contains("data-renderer-version=\"7\""))
        #expect(upgraded.document.contains("data-renderer-version=\"8\""))
    }

    @Test("Cancelled rendering does not publish partial output")
    func cancellation() async {
        let renderer = MarkdownRenderingService()
        let task = Task {
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            return try await renderer.render(request("A cancellable paragraph."))
        }

        do {
            _ = try await task.value
            Issue.record("Expected rendering to observe cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected rendering error: \(error)")
        }
    }

    private func request(_ markdown: String) -> MarkdownRenderRequest {
        MarkdownRenderRequest(markdown: markdown, bookID: bookID, mode: .readerHTML)
    }

    private func fixture(named name: String) throws -> String {
        let fileURL = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/Rendering/\(name)", directoryHint: .notDirectory)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func makeAsset(id: UUID, bookID: UUID, checksum: String) -> Asset {
        Asset(
            id: id,
            bookID: bookID,
            purpose: .chapterImage,
            mediaType: "image/png",
            storageRelativePath: "Assets/Books/\(bookID.databaseString)/\(id.databaseString).png",
            checksum: checksum,
            byteCount: 4
        )
    }

    private func blockID(containing text: String, in document: String) -> String? {
        guard let textRange = document.range(of: ">\(text)</p>") else { return nil }
        let prefix = document[..<textRange.lowerBound]
        guard let openingRange = prefix.range(of: "<p id=\"", options: .backwards) else { return nil }
        let idStart = openingRange.upperBound
        guard let idEnd = prefix[idStart...].firstIndex(of: "\"") else { return nil }
        return String(prefix[idStart..<idEnd])
    }

    private func parseXML(_ document: String) -> String? {
        let delegate = XMLValidationDelegate()
        let parser = XMLParser(data: Data(document.utf8))
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        return parser.parse() ? nil : delegate.errorMessage ?? parser.parserError?.localizedDescription
    }
}

nonisolated private final class XMLValidationDelegate: NSObject, XMLParserDelegate {
    private(set) var errorMessage: String?

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        errorMessage = parseError.localizedDescription
    }
}
