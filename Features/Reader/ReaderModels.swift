import Foundation
import Observation

nonisolated struct ReaderWindowRoute: Codable, Hashable, Sendable {
    let bookID: UUID
}

nonisolated enum ReaderFontFamily: String, CaseIterable, Codable, Sendable {
    case serif
    case sansSerif
    case system
    case monospaced

    var title: String {
        switch self {
        case .serif:
            "Serif"
        case .sansSerif:
            "Sans Serif"
        case .system:
            "System"
        case .monospaced:
            "Monospaced"
        }
    }

    fileprivate var cssValue: String {
        switch self {
        case .serif:
            "ui-serif, Georgia, 'Times New Roman', serif"
        case .sansSerif:
            "ui-sans-serif, -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif"
        case .system:
            "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif"
        case .monospaced:
            "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace"
        }
    }
}

nonisolated enum ReaderTheme: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case sepia
    case dark

    var title: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .sepia:
            "Sepia"
        case .dark:
            "Dark"
        }
    }

    fileprivate var css: String {
        switch self {
        case .system:
            """
            :root {
              color-scheme: light dark;
            }
            """
        case .light:
            """
            :root {
              color-scheme: light;
              --page: #ffffff;
              --text: #202124;
              --secondary: #62666d;
              --accent: #315f9b;
              --border: #d9dce1;
              --surface: #f5f6f8;
              --quote: #e8eef7;
              --warning: #fff4d6;
            }
            """
        case .sepia:
            """
            :root {
              color-scheme: light;
              --page: #f4ecd8;
              --text: #3f3527;
              --secondary: #746552;
              --accent: #785d35;
              --border: #cbbd9f;
              --surface: #e8dcc2;
              --quote: #e4d5b6;
              --warning: #ead6a4;
            }
            """
        case .dark:
            """
            :root {
              color-scheme: dark;
              --page: #1d1d1f;
              --text: #f2f2f4;
              --secondary: #b2b4ba;
              --accent: #8ab4ef;
              --border: #45464c;
              --surface: #292a2f;
              --quote: #27364b;
              --warning: #4b3b18;
            }
            """
        }
    }
}

nonisolated struct ReaderPreferences: Equatable, Hashable, Sendable {
    static let fontSizeRange = 15.0...28.0
    static let lineHeightRange = 1.3...2.0
    static let contentWidthRange = 55.0...92.0

    static let defaults = ReaderPreferences(
        fontFamily: .serif,
        fontSize: 18,
        lineHeight: 1.65,
        contentWidth: 82,
        theme: .system
    )

    let fontFamily: ReaderFontFamily
    let fontSize: Double
    let lineHeight: Double
    let contentWidth: Double
    let theme: ReaderTheme

    init(
        fontFamily: ReaderFontFamily,
        fontSize: Double,
        lineHeight: Double,
        contentWidth: Double,
        theme: ReaderTheme
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize.clamped(to: Self.fontSizeRange)
        self.lineHeight = lineHeight.clamped(to: Self.lineHeightRange)
        self.contentWidth = contentWidth.clamped(to: Self.contentWidthRange)
        self.theme = theme
    }
}

@MainActor
@Observable
final class ReaderSettingsStore {
    private enum Key {
        static let fontFamily = "reader.fontFamily"
        static let fontSize = "reader.fontSize"
        static let lineHeight = "reader.lineHeight"
        static let contentWidth = "reader.contentWidthPercent"
        static let theme = "reader.theme"
    }

    private let defaults: UserDefaults

    var fontFamily: ReaderFontFamily { didSet { persist() } }
    var fontSize: Double { didSet { persist() } }
    var lineHeight: Double { didSet { persist() } }
    var contentWidth: Double { didSet { persist() } }
    var theme: ReaderTheme { didSet { persist() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let fallback = ReaderPreferences.defaults
        let storedPreferences = ReaderPreferences(
            fontFamily: defaults.string(forKey: Key.fontFamily).flatMap(ReaderFontFamily.init(rawValue:))
                ?? fallback.fontFamily,
            fontSize: defaults.object(forKey: Key.fontSize) == nil
                ? fallback.fontSize
                : defaults.double(forKey: Key.fontSize),
            lineHeight: defaults.object(forKey: Key.lineHeight) == nil
                ? fallback.lineHeight
                : defaults.double(forKey: Key.lineHeight),
            contentWidth: defaults.object(forKey: Key.contentWidth) == nil
                ? fallback.contentWidth
                : defaults.double(forKey: Key.contentWidth),
            theme: defaults.string(forKey: Key.theme).flatMap(ReaderTheme.init(rawValue:))
                ?? fallback.theme
        )
        fontFamily = storedPreferences.fontFamily
        fontSize = storedPreferences.fontSize
        lineHeight = storedPreferences.lineHeight
        contentWidth = storedPreferences.contentWidth
        theme = storedPreferences.theme
    }

    var preferences: ReaderPreferences {
        ReaderPreferences(
            fontFamily: fontFamily,
            fontSize: fontSize,
            lineHeight: lineHeight,
            contentWidth: contentWidth,
            theme: theme
        )
    }

    func reset() {
        let fallback = ReaderPreferences.defaults
        fontFamily = fallback.fontFamily
        fontSize = fallback.fontSize
        lineHeight = fallback.lineHeight
        contentWidth = fallback.contentWidth
        theme = fallback.theme
        persist()
    }

    private func persist() {
        defaults.set(fontFamily.rawValue, forKey: Key.fontFamily)
        defaults.set(fontSize.clamped(to: ReaderPreferences.fontSizeRange), forKey: Key.fontSize)
        defaults.set(lineHeight.clamped(to: ReaderPreferences.lineHeightRange), forKey: Key.lineHeight)
        defaults.set(contentWidth.clamped(to: ReaderPreferences.contentWidthRange), forKey: Key.contentWidth)
        defaults.set(theme.rawValue, forKey: Key.theme)
    }
}

nonisolated struct ReaderChapterNavigator: Equatable, Sendable {
    private(set) var chapters: [Chapter] = []
    private(set) var selectedChapterID: Chapter.ID?

    var selectedChapter: Chapter? {
        guard let selectedChapterID else { return nil }
        return chapters.first { $0.id == selectedChapterID }
    }

    var selectedIndex: Int? {
        guard let selectedChapterID else { return nil }
        return chapters.firstIndex { $0.id == selectedChapterID }
    }

    var canMovePrevious: Bool {
        guard let selectedIndex else { return false }
        return selectedIndex > chapters.startIndex
    }

    var canMoveNext: Bool {
        guard let selectedIndex else { return false }
        return selectedIndex < chapters.index(before: chapters.endIndex)
    }

    mutating func updateChapters(
        _ observedChapters: [Chapter],
        preferredChapterID: Chapter.ID? = nil
    ) {
        chapters = observedChapters.sorted {
            if $0.position != $1.position {
                return $0.position < $1.position
            }
            return $0.id.databaseString < $1.id.databaseString
        }

        if let selectedChapterID, chapters.contains(where: { $0.id == selectedChapterID }) {
            return
        }
        if let preferredChapterID,
           chapters.contains(where: { $0.id == preferredChapterID }) {
            selectedChapterID = preferredChapterID
        } else {
            selectedChapterID = chapters.first?.id
        }
    }

    @discardableResult
    mutating func select(_ chapterID: Chapter.ID) -> Bool {
        guard chapters.contains(where: { $0.id == chapterID }) else { return false }
        selectedChapterID = chapterID
        return true
    }

    @discardableResult
    mutating func movePrevious() -> Bool {
        guard let selectedIndex, canMovePrevious else { return false }
        selectedChapterID = chapters[chapters.index(before: selectedIndex)].id
        return true
    }

    @discardableResult
    mutating func moveNext() -> Bool {
        guard let selectedIndex, canMoveNext else { return false }
        selectedChapterID = chapters[chapters.index(after: selectedIndex)].id
        return true
    }
}

nonisolated struct ReaderBookSearchResult: Identifiable, Equatable, Sendable {
    let chapterID: Chapter.ID
    let chapterTitle: String
    let snippet: String
    let matchCount: Int

    var id: Chapter.ID { chapterID }
}

actor ReaderBookSearchService {
    func results(for query: String, in chapters: [Chapter]) -> [ReaderBookSearchResult] {
        var results: [ReaderBookSearchResult] = []
        for chapter in chapters {
            guard !Task.isCancelled else { return [] }
            if let result = ReaderBookSearch.result(for: query, in: chapter) {
                results.append(result)
            }
        }
        return results
    }
}

nonisolated enum ReaderBookSearch {
    private static let comparisonOptions: String.CompareOptions = [
        .caseInsensitive,
        .diacriticInsensitive,
        .widthInsensitive,
    ]
    private static let comparisonLocale = Locale(identifier: "en_US_POSIX")

    static func results(for query: String, in chapters: [Chapter]) -> [ReaderBookSearchResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        return chapters.compactMap { result(for: query, in: $0) }
    }

    fileprivate static func result(
        for query: String,
        in chapter: Chapter
    ) -> ReaderBookSearchResult? {
        let titleMatches = occurrenceCount(of: query, in: chapter.title)
        let bodyMatches = occurrenceCount(of: query, in: chapter.markdown)
        guard titleMatches + bodyMatches > 0 else { return nil }

        return ReaderBookSearchResult(
            chapterID: chapter.id,
            chapterTitle: chapter.title,
            snippet: bodyMatches > 0
                ? snippet(for: query, in: chapter.markdown)
                : "Match in chapter title",
            matchCount: titleMatches + bodyMatches
        )
    }

    private static func occurrenceCount(of query: String, in text: String) -> Int {
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let match = text.range(
            of: query,
            options: comparisonOptions,
            range: searchRange,
            locale: comparisonLocale
        ) {
            count += 1
            searchRange = match.upperBound..<text.endIndex
        }
        return count
    }

    private static func snippet(for query: String, in text: String) -> String {
        let collapsed = text.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
        guard let match = collapsed.range(
            of: query,
            options: comparisonOptions,
            locale: comparisonLocale
        ) else {
            return "Match in chapter content"
        }

        let start = collapsed.index(match.lowerBound, offsetBy: -44, limitedBy: collapsed.startIndex)
            ?? collapsed.startIndex
        let end = collapsed.index(match.upperBound, offsetBy: 72, limitedBy: collapsed.endIndex)
            ?? collapsed.endIndex
        let prefix = start == collapsed.startIndex ? "" : "…"
        let suffix = end == collapsed.endIndex ? "" : "…"
        return prefix + collapsed[start..<end] + suffix
    }
}

nonisolated enum ReaderDocumentStyler {
    enum StylingError: LocalizedError, Equatable {
        case missingHead

        var errorDescription: String? {
            switch self {
            case .missingHead:
                "The rendered chapter document is missing its expected head element."
            }
        }
    }

    static func apply(_ preferences: ReaderPreferences, to html: String) throws -> String {
        guard let insertionRange = html.range(of: "</head>", options: [.caseInsensitive]) else {
            throw StylingError.missingHead
        }

        let fontSize = cssNumber(preferences.fontSize)
        let lineHeight = cssNumber(preferences.lineHeight)
        let contentWidth = cssNumber(preferences.contentWidth)
        let style = """

        <style id="reader-preferences">
        \(preferences.theme.css)
        body {
          font-family: \(preferences.fontFamily.cssValue);
          font-size: \(fontSize)px;
          line-height: \(lineHeight);
        }
        .chapter {
          width: \(contentWidth)%;
          max-width: 88rem;
        }
        </style>
        """

        var styledHTML = html
        styledHTML.insert(contentsOf: style, at: insertionRange.lowerBound)
        return styledHTML
    }

    private static func cssNumber(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

nonisolated enum ReaderURLDecision: Equatable, Sendable {
    case allowTrustedDocument
    case openExternally
    case block
}

nonisolated enum ReaderURLPolicy {
    static func decision(for url: URL, isUserActivatedLink: Bool) -> ReaderURLDecision {
        if isTrustedDocumentURL(url) {
            return .allowTrustedDocument
        }

        guard isUserActivatedLink else { return .block }
        switch url.scheme?.lowercased() {
        case "http", "https", "mailto":
            return .openExternally
        default:
            return .block
        }
    }

    private static func isTrustedDocumentURL(_ url: URL) -> Bool {
        let documentURL = url.absoluteString.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first.map(String.init) ?? ""
        return documentURL.caseInsensitiveCompare("about:blank") == .orderedSame
    }
}

nonisolated private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
