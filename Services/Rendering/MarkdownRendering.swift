import CryptoKit
import Foundation
import Markdown

nonisolated enum MarkdownOutputMode: String, Hashable, Sendable {
    case readerHTML
    case epubXHTML
}

nonisolated struct MarkdownRenderRequest: Sendable {
    let markdown: String
    let bookID: UUID
    let assets: [Asset]
    let mode: MarkdownOutputMode
    let documentTitle: String
    let language: String

    init(
        markdown: String,
        bookID: UUID,
        assets: [Asset] = [],
        mode: MarkdownOutputMode,
        documentTitle: String = "Chapter",
        language: String = "en"
    ) {
        self.markdown = markdown
        self.bookID = bookID
        self.assets = assets
        self.mode = mode
        self.documentTitle = documentTitle
        self.language = language
    }
}

nonisolated struct MarkdownRenderCacheKey: Equatable, Hashable, Sendable {
    let sourceHash: String
    let rendererVersion: Int
    let mode: MarkdownOutputMode
    let bookID: UUID
    let assetFingerprint: String
    let documentMetadataFingerprint: String
}

nonisolated enum MarkdownRenderIssue: Hashable, Sendable {
    case rawHTMLRenderedAsText
    case unsafeLinkOmitted
    case unavailableImage
    case unsupportedMarkupRenderedAsText

    var message: String {
        switch self {
        case .rawHTMLRenderedAsText:
            "Raw HTML was displayed as source text and was not executed."
        case .unsafeLinkOmitted:
            "An unsafe or unsupported link destination was omitted."
        case .unavailableImage:
            "An image was omitted because it was not a registered asset for this book."
        case .unsupportedMarkupRenderedAsText:
            "Unsupported Markdown syntax was displayed as source text."
        }
    }
}

nonisolated struct MarkdownRenderResult: Equatable, Sendable {
    let document: String
    let cacheKey: MarkdownRenderCacheKey
    let blockIDs: [String]
    let blocks: [MarkdownRenderedBlock]
    let issues: [MarkdownRenderIssue]
}

nonisolated struct MarkdownRenderedBlock: Equatable, Hashable, Sendable {
    let id: String
    let normalizedText: String
}

nonisolated enum MarkdownSearchTextExtractor {
    static func blocks(from markdown: String) -> [MarkdownRenderedBlock] {
        let document = Document(parsing: markdown)
        var renderer = ControlledHTMLBodyRenderer(
            mode: .readerHTML,
            bookID: UUID(),
            assets: []
        )
        _ = renderer.visit(document)
        return renderer.blocks
    }
}

nonisolated protocol MarkdownRendering: Sendable {
    func render(_ request: MarkdownRenderRequest) async throws -> MarkdownRenderResult
}

actor MarkdownRenderingService: MarkdownRendering {
    static let currentRendererVersion = 1

    let rendererVersion: Int
    private let cacheCapacity: Int
    private var cache: [MarkdownRenderCacheKey: MarkdownRenderResult] = [:]
    private var cacheOrder: [MarkdownRenderCacheKey] = []
    private(set) var uncachedRenderCount = 0

    init(
        rendererVersion: Int = MarkdownRenderingService.currentRendererVersion,
        cacheCapacity: Int = 32
    ) {
        self.rendererVersion = rendererVersion
        self.cacheCapacity = max(1, cacheCapacity)
    }

    func render(_ request: MarkdownRenderRequest) async throws -> MarkdownRenderResult {
        let cacheKey = Self.cacheKey(for: request, rendererVersion: rendererVersion)
        if let cached = cache[cacheKey] {
            touch(cacheKey)
            return cached
        }

        try Task.checkCancellation()
        uncachedRenderCount += 1

        let document = Document(parsing: request.markdown)
        var bodyRenderer = ControlledHTMLBodyRenderer(
            mode: request.mode,
            bookID: request.bookID,
            assets: request.assets
        )
        let body = bodyRenderer.visit(document)

        if bodyRenderer.wasCancelled || Task.isCancelled {
            throw CancellationError()
        }

        let renderedDocument = HTMLDocumentBuilder.build(
            body: body,
            mode: request.mode,
            title: request.documentTitle,
            language: request.language,
            rendererVersion: rendererVersion
        )
        let result = MarkdownRenderResult(
            document: renderedDocument,
            cacheKey: cacheKey,
            blockIDs: bodyRenderer.blockIDs,
            blocks: bodyRenderer.blocks,
            issues: bodyRenderer.issues
        )
        insert(result, for: cacheKey)
        return result
    }

    func clearCache() {
        cache.removeAll(keepingCapacity: true)
        cacheOrder.removeAll(keepingCapacity: true)
    }

    private func insert(_ result: MarkdownRenderResult, for key: MarkdownRenderCacheKey) {
        cache[key] = result
        touch(key)
        while cacheOrder.count > cacheCapacity {
            let evictedKey = cacheOrder.removeFirst()
            cache.removeValue(forKey: evictedKey)
        }
    }

    private func touch(_ key: MarkdownRenderCacheKey) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
    }

    private static func cacheKey(
        for request: MarkdownRenderRequest,
        rendererVersion: Int
    ) -> MarkdownRenderCacheKey {
        let assetDescription = request.assets
            .filter { $0.bookID == request.bookID }
            .sorted { $0.id.databaseString < $1.id.databaseString }
            .map { "\($0.id.databaseString):\($0.checksum):\($0.mediaType)" }
            .joined(separator: "\n")
        let documentMetadata = "\(request.documentTitle)\u{0}\(request.language)"

        return MarkdownRenderCacheKey(
            sourceHash: SHA256.hexDigest(of: request.markdown),
            rendererVersion: rendererVersion,
            mode: request.mode,
            bookID: request.bookID,
            assetFingerprint: SHA256.hexDigest(of: assetDescription),
            documentMetadataFingerprint: SHA256.hexDigest(of: documentMetadata)
        )
    }
}

nonisolated private struct ControlledHTMLBodyRenderer: MarkupVisitor {
    typealias Result = String

    let mode: MarkdownOutputMode
    let bookID: UUID
    let assetsByID: [UUID: Asset]

    private(set) var issues: [MarkdownRenderIssue] = []
    private(set) var blockIDs: [String] = []
    private(set) var blocks: [MarkdownRenderedBlock] = []
    private(set) var wasCancelled = false
    private var blockOccurrences: [String: Int] = [:]
    private var tableAlignments: [Table.ColumnAlignment?] = []
    private var currentTableColumn = 0
    private var isInTableHead = false

    init(mode: MarkdownOutputMode, bookID: UUID, assets: [Asset]) {
        self.mode = mode
        self.bookID = bookID
        assetsByID = Dictionary(
            uniqueKeysWithValues: assets
                .filter { $0.bookID == bookID }
                .map { ($0.id, $0) }
        )
    }

    mutating func defaultVisit(_ markup: Markup) -> String {
        renderChildren(of: markup)
    }

    mutating func visitDocument(_ document: Document) -> String {
        renderChildren(of: document)
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let id = blockID(for: heading, kind: "heading-\(heading.level)")
        return "<h\(heading.level) id=\"\(id)\">\(renderChildren(of: heading))</h\(heading.level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        let id = blockID(for: paragraph, kind: "paragraph")
        return "<p id=\"\(id)\">\(renderChildren(of: paragraph))</p>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        let id = blockID(for: blockQuote, kind: "blockquote")
        return "<blockquote id=\"\(id)\">\n\(renderChildren(of: blockQuote))</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let id = blockID(for: codeBlock, kind: "code-block")
        let languageClass: String
        if let language = codeBlock.language,
           let safeLanguage = safeCSSIdentifier(language) {
            languageClass = " class=\"language-\(safeLanguage)\""
        } else {
            languageClass = ""
        }
        return "<pre id=\"\(id)\"><code\(languageClass)>\(escapeText(codeBlock.code))</code></pre>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        let id = blockID(for: thematicBreak, kind: "thematic-break")
        return mode == .epubXHTML
            ? "<hr id=\"\(id)\" />\n"
            : "<hr id=\"\(id)\">\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        let id = blockID(for: orderedList, kind: "ordered-list")
        let start = orderedList.startIndex == 1 ? "" : " start=\"\(orderedList.startIndex)\""
        return "<ol id=\"\(id)\"\(start)>\n\(renderChildren(of: orderedList))</ol>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        let id = blockID(for: unorderedList, kind: "unordered-list")
        return "<ul id=\"\(id)\">\n\(renderChildren(of: unorderedList))</ul>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        let id = blockID(for: listItem, kind: "list-item")
        guard let checkbox = listItem.checkbox else {
            return "<li id=\"\(id)\">\(renderChildren(of: listItem))</li>\n"
        }

        let checked = checkbox == .checked ? " checked=\"checked\"" : ""
        let stateLabel = checkbox == .checked ? "Completed task" : "Incomplete task"
        let closing = mode == .epubXHTML ? " />" : ">"
        let input = "<input type=\"checkbox\" disabled=\"disabled\" aria-label=\"\(stateLabel)\"\(checked)\(closing)"
        return "<li id=\"\(id)\" class=\"task-list-item\">\(input) \(renderChildren(of: listItem))</li>\n"
    }

    mutating func visitTable(_ table: Table) -> String {
        let id = blockID(for: table, kind: "table")
        let previousAlignments = tableAlignments
        tableAlignments = table.columnAlignments
        let contents = renderChildren(of: table)
        tableAlignments = previousAlignments
        return "<div id=\"\(id)\" class=\"table-scroll\"><table>\n\(contents)</table></div>\n"
    }

    mutating func visitTableHead(_ tableHead: Table.Head) -> String {
        let previousValue = isInTableHead
        isInTableHead = true
        currentTableColumn = 0
        let result = "<thead><tr>\n\(renderChildren(of: tableHead))</tr></thead>\n"
        isInTableHead = previousValue
        return result
    }

    mutating func visitTableBody(_ tableBody: Table.Body) -> String {
        guard !tableBody.isEmpty else { return "" }
        return "<tbody>\n\(renderChildren(of: tableBody))</tbody>\n"
    }

    mutating func visitTableRow(_ tableRow: Table.Row) -> String {
        currentTableColumn = 0
        return "<tr>\n\(renderChildren(of: tableRow))</tr>\n"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) -> String {
        guard tableCell.colspan > 0, tableCell.rowspan > 0 else { return "" }
        let element = isInTableHead ? "th" : "td"
        let alignment = alignmentClass(at: currentTableColumn)
        currentTableColumn += max(1, Int(tableCell.colspan))
        let colspan = tableCell.colspan > 1 ? " colspan=\"\(tableCell.colspan)\"" : ""
        let rowspan = tableCell.rowspan > 1 ? " rowspan=\"\(tableCell.rowspan)\"" : ""
        return "<\(element)\(alignment)\(colspan)\(rowspan)>\(renderChildren(of: tableCell))</\(element)>\n"
    }

    mutating func visitText(_ text: Text) -> String {
        escapeText(text.string)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(renderChildren(of: emphasis))</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(renderChildren(of: strong))</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>\(renderChildren(of: strikethrough))</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(escapeText(inlineCode.code))</code>"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        mode == .epubXHTML ? "<br />\n" : "<br>\n"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        "\n"
    }

    mutating func visitLink(_ link: Link) -> String {
        let label = renderChildren(of: link)
        guard let destination = link.destination,
              let safeDestination = safeLinkDestination(destination) else {
            addIssue(.unsafeLinkOmitted)
            return "<span class=\"unsafe-link\">\(label)</span>"
        }

        let title = link.title.map { " title=\"\(escapeAttribute($0))\"" } ?? ""
        let relationship = mode == .readerHTML ? " rel=\"noopener noreferrer\"" : ""
        return "<a href=\"\(escapeAttribute(safeDestination))\"\(title)\(relationship)>\(label)</a>"
    }

    mutating func visitImage(_ image: Image) -> String {
        let alternativeText = PlainTextRenderer.render(image).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let source = image.source,
              let safeSource = resolvedAssetSource(source) else {
            addIssue(.unavailableImage)
            let description = alternativeText.isEmpty ? "Image unavailable" : "Image unavailable: \(alternativeText)"
            return "<span class=\"unavailable-image\" role=\"img\" aria-label=\"\(escapeAttribute(description))\">\(escapeText(description))</span>"
        }

        let title = image.title.map { " title=\"\(escapeAttribute($0))\"" } ?? ""
        let closing = mode == .epubXHTML ? " />" : ">"
        return "<img src=\"\(escapeAttribute(safeSource))\" alt=\"\(escapeAttribute(alternativeText))\"\(title)\(closing)"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        addIssue(.rawHTMLRenderedAsText)
        let id = blockID(for: html, kind: "raw-html")
        return "<pre id=\"\(id)\" class=\"raw-html\"><code>\(escapeText(html.rawHTML))</code></pre>\n"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        addIssue(.rawHTMLRenderedAsText)
        return "<code class=\"raw-html-inline\">\(escapeText(inlineHTML.rawHTML))</code>"
    }

    mutating func visitCustomBlock(_ customBlock: CustomBlock) -> String {
        unsupportedBlock(customBlock)
    }

    mutating func visitBlockDirective(_ blockDirective: BlockDirective) -> String {
        unsupportedBlock(blockDirective)
    }

    mutating func visitDoxygenDiscussion(_ doxygenDiscussion: DoxygenDiscussion) -> String {
        unsupportedBlock(doxygenDiscussion)
    }

    mutating func visitDoxygenNote(_ doxygenNote: DoxygenNote) -> String {
        unsupportedBlock(doxygenNote)
    }

    mutating func visitDoxygenAbstract(_ doxygenAbstract: DoxygenAbstract) -> String {
        unsupportedBlock(doxygenAbstract)
    }

    mutating func visitDoxygenParameter(_ doxygenParam: DoxygenParameter) -> String {
        unsupportedBlock(doxygenParam)
    }

    mutating func visitDoxygenReturns(_ doxygenReturns: DoxygenReturns) -> String {
        unsupportedBlock(doxygenReturns)
    }

    mutating func visitCustomInline(_ customInline: CustomInline) -> String {
        unsupportedInline(customInline)
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) -> String {
        unsupportedInline(symbolLink)
    }

    mutating func visitInlineAttributes(_ attributes: InlineAttributes) -> String {
        unsupportedInline(attributes)
    }

    private mutating func renderChildren(of markup: Markup) -> String {
        var result = ""
        for child in markup.children {
            if Task.isCancelled {
                wasCancelled = true
                break
            }
            result += visit(child)
        }
        return result
    }

    private mutating func blockID(for markup: Markup, kind: String) -> String {
        let semanticSource = markup.format()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fingerprint = SHA256.hexDigest(of: "\(kind)\u{0}\(semanticSource)")
        let shortFingerprint = String(fingerprint.prefix(16))
        let occurrence = blockOccurrences[shortFingerprint, default: 0] + 1
        blockOccurrences[shortFingerprint] = occurrence
        let id = occurrence == 1
            ? "block-\(shortFingerprint)"
            : "block-\(shortFingerprint)-\(occurrence)"
        blockIDs.append(id)
        blocks.append(
            MarkdownRenderedBlock(
                id: id,
                normalizedText: normalizedAnchorText(PlainTextRenderer.render(markup))
            )
        )
        return id
    }

    private mutating func unsupportedBlock(_ markup: Markup) -> String {
        addIssue(.unsupportedMarkupRenderedAsText)
        let id = blockID(for: markup, kind: "unsupported-block")
        return "<pre id=\"\(id)\" class=\"unsupported-markup\"><code>\(escapeText(markup.format()))</code></pre>\n"
    }

    private mutating func unsupportedInline(_ markup: Markup) -> String {
        addIssue(.unsupportedMarkupRenderedAsText)
        return "<code class=\"unsupported-markup-inline\">\(escapeText(markup.format()))</code>"
    }

    private mutating func addIssue(_ issue: MarkdownRenderIssue) {
        if !issues.contains(issue) {
            issues.append(issue)
        }
    }

    private func resolvedAssetSource(_ source: String) -> String? {
        guard let url = URL(string: source),
              let reference = try? BookAssetReference(url: url),
              reference.bookID == bookID,
              let asset = assetsByID[reference.assetID] else {
            return nil
        }

        switch mode {
        case .readerHTML:
            return try? reference.url().absoluteString
        case .epubXHTML:
            return "../Assets/\(asset.id.databaseString).\(safeAssetExtension(asset))"
        }
    }

    private func safeLinkDestination(_ destination: String) -> String? {
        if destination.hasPrefix("#"),
           !destination.dropFirst().contains(where: { $0.isWhitespace }) {
            return destination
        }

        guard let components = URLComponents(string: destination),
              let scheme = components.scheme?.lowercased() else {
            return nil
        }
        if ["https", "http", "mailto"].contains(scheme) {
            return components.url?.absoluteString
        }
        if scheme == BookAssetReference.scheme {
            return resolvedAssetSource(destination)
        }
        return nil
    }

    private func safeAssetExtension(_ asset: Asset) -> String {
        let candidate = URL(filePath: asset.storageRelativePath).pathExtension.lowercased()
        guard !candidate.isEmpty,
              candidate.count <= 12,
              candidate.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            return "bin"
        }
        return candidate
    }

    private func alignmentClass(at index: Int) -> String {
        guard tableAlignments.indices.contains(index),
              let alignment = tableAlignments[index] else {
            return ""
        }
        switch alignment {
        case .left:
            return " class=\"align-left\""
        case .center:
            return " class=\"align-center\""
        case .right:
            return " class=\"align-right\""
        }
    }
}

nonisolated private struct PlainTextRenderer: MarkupVisitor {
    typealias Result = String

    static func render(_ markup: Markup) -> String {
        var renderer = PlainTextRenderer()
        return renderer.visit(markup)
    }

    mutating func defaultVisit(_ markup: Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    mutating func visitText(_ text: Text) -> String {
        text.string
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        inlineCode.code
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        " "
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        " "
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        inlineHTML.rawHTML
    }
}

nonisolated private enum HTMLDocumentBuilder {
    static func build(
        body: String,
        mode: MarkdownOutputMode,
        title: String,
        language: String,
        rendererVersion: Int
    ) -> String {
        let safeLanguage = safeLanguageCode(language)
        let safeTitle = escapeText(title)
        switch mode {
        case .readerHTML:
            return """
            <!doctype html>
            <html lang="\(safeLanguage)">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src book-asset:; style-src 'unsafe-inline';">
            <title>\(safeTitle)</title>
            <style>\(MarkdownStyles.reader)</style>
            </head>
            <body><main class="chapter" data-renderer-version="\(rendererVersion)">
            \(body)</main></body>
            </html>
            """

        case .epubXHTML:
            return """
            <?xml version="1.0" encoding="utf-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="\(safeLanguage)" lang="\(safeLanguage)">
            <head>
            <meta charset="utf-8" />
            <title>\(safeTitle)</title>
            <style type="text/css">\(MarkdownStyles.epub)</style>
            </head>
            <body><section class="chapter" data-renderer-version="\(rendererVersion)">
            \(body)</section></body>
            </html>
            """
        }
    }

    private static func safeLanguageCode(_ language: String) -> String {
        let candidate = language.lowercased()
        guard !candidate.isEmpty,
              candidate.count <= 35,
              candidate.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
            return "en"
        }
        return candidate
    }
}

nonisolated private func safeCSSIdentifier(_ value: String) -> String? {
    let candidate = value.lowercased()
    guard !candidate.isEmpty,
          candidate.count <= 40,
          candidate.allSatisfy({
              $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
          }) else {
        return nil
    }
    return candidate
}

nonisolated private func normalizedAnchorText(_ value: String) -> String {
    value
        .split(whereSeparator: \Character.isWhitespace)
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

nonisolated private func escapeText(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

nonisolated private func escapeAttribute(_ value: String) -> String {
    escapeText(value)
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}

private extension SHA256 {
    nonisolated static func hexDigest(of value: String) -> String {
        hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
