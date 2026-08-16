import Foundation
import Testing
import WebKit
@testable import iEvelyn

@Suite("Reading experience", .serialized)
struct ReaderTests {
    @Test("Chapter navigation sorts deterministically and respects boundaries")
    func chapterNavigationAndBoundaries() {
        let bookID = UUID()
        let first = chapter(bookID: bookID, title: "First", position: 0)
        let middle = chapter(bookID: bookID, title: "Middle", position: 1)
        let last = chapter(bookID: bookID, title: "Last", position: 2)
        var navigator = ReaderChapterNavigator()

        navigator.updateChapters([last, first, middle])
        #expect(navigator.chapters.map(\.id) == [first.id, middle.id, last.id])
        #expect(navigator.selectedChapterID == first.id)
        #expect(!navigator.canMovePrevious)
        #expect(navigator.canMoveNext)
        let movedBeforeStart = navigator.movePrevious()
        #expect(!movedBeforeStart)

        let movedToMiddle = navigator.moveNext()
        #expect(movedToMiddle)
        #expect(navigator.selectedChapterID == middle.id)
        #expect(navigator.canMovePrevious)
        #expect(navigator.canMoveNext)

        let movedToLast = navigator.moveNext()
        #expect(movedToLast)
        #expect(navigator.selectedChapterID == last.id)
        #expect(!navigator.canMoveNext)
        let movedAfterEnd = navigator.moveNext()
        #expect(!movedAfterEnd)
    }

    @Test("Chapter observation preserves a stable selection and recovers after deletion")
    func chapterSelectionAcrossUpdates() {
        let bookID = UUID()
        let first = chapter(bookID: bookID, title: "First", position: 0)
        var second = chapter(bookID: bookID, title: "Second", position: 1)
        let third = chapter(bookID: bookID, title: "Third", position: 2)
        var navigator = ReaderChapterNavigator()

        navigator.updateChapters([first, second, third])
        let selectedSecond = navigator.select(second.id)
        #expect(selectedSecond)

        second.title = "Renamed"
        navigator.updateChapters([third, second, first])
        #expect(navigator.selectedChapterID == second.id)
        #expect(navigator.selectedChapter?.title == "Renamed")

        navigator.updateChapters([first, third])
        #expect(navigator.selectedChapterID == first.id)
        let selectedDeletedChapter = navigator.select(second.id)
        #expect(!selectedDeletedChapter)

        navigator.updateChapters([])
        #expect(navigator.selectedChapterID == nil)
        #expect(!navigator.canMovePrevious)
        #expect(!navigator.canMoveNext)
    }

    @Test("Chapter navigation honors a saved initial chapter")
    func preferredInitialChapter() {
        let bookID = UUID()
        let first = chapter(bookID: bookID, title: "First", position: 0)
        let second = chapter(bookID: bookID, title: "Second", position: 1)
        var navigator = ReaderChapterNavigator()

        navigator.updateChapters([first, second], preferredChapterID: second.id)
        #expect(navigator.selectedChapterID == second.id)

        navigator.updateChapters([first, second], preferredChapterID: first.id)
        #expect(navigator.selectedChapterID == second.id)
    }

    @Test("Semantic anchors use stable IDs, quotes, nearby context, then fractions")
    func semanticAnchorResolution() {
        let originalBlocks = [
            MarkdownRenderedBlock(id: "opening", normalizedText: "Opening context"),
            MarkdownRenderedBlock(id: "saved", normalizedText: "The exact saved paragraph"),
            MarkdownRenderedBlock(id: "following", normalizedText: "Following context"),
        ]
        let anchor = ReaderSemanticAnchor.make(
            from: ReaderLocationCapture(stableBlockID: "saved", fractionInChapter: 0.4),
            blocks: originalBlocks
        )

        #expect(anchor.textQuote == "The exact saved paragraph")
        #expect(anchor.contextBefore == "Opening context")
        #expect(anchor.contextAfter == "Following context")
        #expect(ReaderSemanticAnchor.resolve(anchor, in: originalBlocks).strategy == .stableBlock)

        let changedIDBlocks = [
            originalBlocks[0],
            MarkdownRenderedBlock(id: "new-id", normalizedText: "The exact saved paragraph"),
            originalBlocks[2],
        ]
        let quoteResolution = ReaderSemanticAnchor.resolve(anchor, in: changedIDBlocks)
        #expect(quoteResolution.stableBlockID == "new-id")
        #expect(quoteResolution.strategy == .textQuote)

        let removedBlockResolution = ReaderSemanticAnchor.resolve(
            anchor,
            in: [originalBlocks[0], originalBlocks[2]]
        )
        #expect(removedBlockResolution.stableBlockID == "following")
        #expect(removedBlockResolution.strategy == .nearbyContext)

        let fractionResolution = ReaderSemanticAnchor.resolve(
            ReaderLocationAnchor(fractionInChapter: 0.73),
            in: originalBlocks
        )
        #expect(fractionResolution.stableBlockID == nil)
        #expect(fractionResolution.fractionInChapter == 0.73)
        #expect(fractionResolution.strategy == .fraction)
    }

    @Test("Overall progress maps chapter fractions and fallback chapters")
    func progressCalculations() {
        #expect(ReaderProgressCalculator.overallProgress(
            chapterIndex: 1,
            chapterCount: 4,
            fractionInChapter: 0.5
        ) == 0.375)
        #expect(ReaderProgressCalculator.overallProgress(
            chapterIndex: 99,
            chapterCount: 4,
            fractionInChapter: 2
        ) == 1)
        #expect(ReaderProgressCalculator.chapterIndex(for: 0.62, chapterCount: 4) == 2)
        #expect(ReaderProgressCalculator.chapterIndex(for: 1, chapterCount: 4) == 3)
        #expect(ReaderProgressCalculator.chapterIndex(for: 0.5, chapterCount: 0) == nil)
    }

    @Test("Find in Book matches titles and content with useful chapter snippets")
    func findInBook() {
        let bookID = UUID()
        let opening = Chapter(
            bookID: bookID,
            title: "Opening",
            markdown: "# Opening\n\nThe Café is open. Another cafe appears later.",
            position: 0
        )
        let appendix = Chapter(
            bookID: bookID,
            title: "Café Appendix",
            markdown: "# Reference\n\n餐桌旁边有一本书。",
            position: 1
        )

        let cafeResults = ReaderBookSearch.results(for: "  cafe  ", in: [opening, appendix])
        #expect(cafeResults.map(\.chapterID) == [opening.id, appendix.id])
        #expect(cafeResults.map(\.matchCount) == [2, 1])
        #expect(cafeResults[0].snippet.contains("Café is open"))
        #expect(cafeResults[1].snippet == "Match in chapter title")

        let unicodeResults = ReaderBookSearch.results(for: "餐桌", in: [opening, appendix])
        #expect(unicodeResults.map(\.chapterID) == [appendix.id])
        #expect(ReaderBookSearch.results(for: "   ", in: [opening, appendix]).isEmpty)
    }

    @Test("Reader document generation applies only controlled preference CSS")
    func documentGeneration() async throws {
        let renderer = MarkdownRenderingService()
        let result = try await renderer.render(
            MarkdownRenderRequest(
                markdown: "# Opening\n\nA safe [link](https://example.com).",
                bookID: UUID(),
                mode: .readerHTML,
                documentTitle: "Opening"
            )
        )
        let preferences = ReaderPreferences(
            fontFamily: .monospaced,
            fontSize: 22,
            lineHeight: 1.8,
            contentWidth: 72,
            theme: .sepia
        )
        let document = try ReaderDocumentStyler.apply(preferences, to: result.document)

        #expect(document.contains("Content-Security-Policy"))
        #expect(document.contains("<style id=\"reader-preferences\">"))
        #expect(document.contains("font-family: ui-monospace"))
        #expect(document.contains("font-size: 22.00px"))
        #expect(document.contains("line-height: 1.80"))
        #expect(document.contains("width: 72.00%"))
        #expect(document.contains("max-width: 88rem"))
        #expect(document.contains("--page: #f4ecd8"))
        #expect(document.contains("href=\"https://example.com\""))
        #expect(document.range(of: "reader-preferences")!.lowerBound < document.range(of: "</head>")!.lowerBound)
    }

    @Test("Reader preferences clamp invalid persisted numbers")
    func preferencesClampRanges() {
        let preferences = ReaderPreferences(
            fontFamily: .serif,
            fontSize: 100,
            lineHeight: 0,
            contentWidth: 2_000,
            theme: .dark
        )

        #expect(preferences.fontSize == ReaderPreferences.fontSizeRange.upperBound)
        #expect(preferences.lineHeight == ReaderPreferences.lineHeightRange.lowerBound)
        #expect(preferences.contentWidth == ReaderPreferences.contentWidthRange.upperBound)
    }

    @MainActor
    @Test("Reader settings persist across windows and can be reset")
    func settingsPersistence() throws {
        let suiteName = "ReaderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(624, forKey: "reader.contentWidth")
        let firstWindow = ReaderSettingsStore(defaults: defaults)
        #expect(firstWindow.contentWidth == ReaderPreferences.defaults.contentWidth)
        firstWindow.fontFamily = .sansSerif
        firstWindow.fontSize = 24
        firstWindow.lineHeight = 1.9
        firstWindow.contentWidth = 88
        firstWindow.theme = .dark

        let secondWindow = ReaderSettingsStore(defaults: defaults)
        #expect(secondWindow.preferences == ReaderPreferences(
            fontFamily: .sansSerif,
            fontSize: 24,
            lineHeight: 1.9,
            contentWidth: 88,
            theme: .dark
        ))

        secondWindow.reset()
        let thirdWindow = ReaderSettingsStore(defaults: defaults)
        #expect(thirdWindow.preferences == .defaults)
    }

    @Test("Only trusted reader documents and explicit external links may navigate")
    func safeURLHandling() throws {
        #expect(ReaderURLPolicy.decision(
            for: try #require(URL(string: "about:blank")),
            isUserActivatedLink: false
        ) == .allowTrustedDocument)
        #expect(ReaderURLPolicy.decision(
            for: try #require(URL(string: "about:blank#section")),
            isUserActivatedLink: true
        ) == .allowTrustedDocument)
        #expect(ReaderURLPolicy.decision(
            for: try #require(URL(string: "about:blank?unexpected=true")),
            isUserActivatedLink: false
        ) == .block)
        #expect(ReaderURLPolicy.decision(
            for: try #require(URL(string: "about:srcdoc")),
            isUserActivatedLink: false
        ) == .block)
        #expect(ReaderURLPolicy.decision(
            for: try #require(URL(string: "https://example.com/read")),
            isUserActivatedLink: true
        ) == .openExternally)
        #expect(ReaderURLPolicy.decision(
            for: try #require(URL(string: "mailto:reader@example.com")),
            isUserActivatedLink: true
        ) == .openExternally)
        #expect(ReaderURLPolicy.decision(
            for: try #require(URL(string: "https://example.com/redirect")),
            isUserActivatedLink: false
        ) == .block)
        #expect(ReaderURLPolicy.decision(
            for: try #require(URL(string: "javascript:alert(1)")),
            isUserActivatedLink: true
        ) == .block)
        #expect(ReaderURLPolicy.decision(
            for: try #require(URL(string: "file:///private/secret")),
            isUserActivatedLink: true
        ) == .block)
        #expect(ReaderURLPolicy.decision(
            for: try #require(URL(string: "book-asset://book/asset")),
            isUserActivatedLink: true
        ) == .block)
    }

    @Test("Malformed rendered documents fail visibly instead of being partially styled")
    func malformedDocumentFails() {
        #expect(throws: ReaderDocumentStyler.StylingError.missingHead) {
            try ReaderDocumentStyler.apply(.defaults, to: "<html><body>Incomplete</body></html>")
        }
    }

    @MainActor
    @Test("WebKit's internal reader document URL passes the trusted navigation policy")
    func webKitDocumentURLPolicy() async throws {
        let probe = ReaderNavigationProbe()
        let loader = BookAssetDataLoader(repository: ReaderProbeRepository())
        let page = WebPage(
            configuration: BookContentWebConfiguration.make(assetLoader: loader),
            navigationDecider: ReaderProbeNavigationDecider(probe: probe)
        )
        for try await _ in page.load(html: "<html><body>Probe</body></html>") {}
        #expect(probe.decisions == [.allowTrustedDocument])
    }

    @MainActor
    @Test("App-owned location calls work while book content JavaScript stays disabled")
    func webKitLocationCaptureAndRestore() async throws {
        let loader = BookAssetDataLoader(repository: ReaderProbeRepository())
        let page = WebPage(
            configuration: BookContentWebConfiguration.make(assetLoader: loader),
            navigationDecider: ReaderProbeNavigationDecider(probe: ReaderNavigationProbe())
        )
        let document = """
            <html><head><style>
            body { margin: 0; }
            .spacer { height: 900px; }
            #saved { height: 400px; }
            </style></head><body><main class="chapter">
            <div id="top" class="spacer">Top</div>
            <div id="saved">Saved location</div>
            <div id="bottom" class="spacer">Bottom</div>
            </main></body></html>
            """
        for try await _ in page.load(html: document) {}

        let didFindBlock = try await ReaderWebLocationBridge.restore(
            ReaderResolvedLocation(
                stableBlockID: "saved",
                fractionInChapter: 0,
                strategy: .stableBlock
            ),
            in: page
        )
        #expect(didFindBlock)
        let captured = try await ReaderWebLocationBridge.capture(from: page)
        #expect(captured.stableBlockID == "saved")
        #expect(captured.fractionInChapter > 0.25)

        let usedFraction = try await ReaderWebLocationBridge.restore(
            ReaderResolvedLocation(
                stableBlockID: "missing",
                fractionInChapter: 0.8,
                strategy: .fraction
            ),
            in: page
        )
        #expect(!usedFraction)
        let fractionalCapture = try await ReaderWebLocationBridge.capture(from: page)
        #expect(fractionalCapture.fractionInChapter > 0.7)
    }

    private func chapter(bookID: UUID, title: String, position: Int) -> Chapter {
        Chapter(
            bookID: bookID,
            title: title,
            markdown: "# \(title)",
            position: position
        )
    }
}

@MainActor
private final class ReaderNavigationProbe {
    private(set) var decisions: [ReaderURLDecision] = []

    func record(_ action: WebPage.NavigationAction) {
        guard let url = action.request.url else { return }
        decisions.append(ReaderURLPolicy.decision(
            for: url,
            isUserActivatedLink: action.navigationType == .linkActivated
        ))
    }
}

@MainActor
private struct ReaderProbeNavigationDecider: WebPage.NavigationDeciding {
    let probe: ReaderNavigationProbe

    mutating func decidePolicy(
        for action: WebPage.NavigationAction,
        preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        preferences.allowsContentJavaScript = false
        probe.record(action)
        return .allow
    }
}

private nonisolated struct ReaderProbeRepository: LibraryRepository {
    func observeLibraryBooks() -> AsyncThrowingStream<[LibraryBook], Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
