import Foundation

nonisolated struct ReaderLocationAnchor: Equatable, Sendable {
    var stableBlockID: String?
    var textQuote: String?
    var contextBefore: String?
    var contextAfter: String?
    var fractionInChapter: Double

    init(
        stableBlockID: String? = nil,
        textQuote: String? = nil,
        contextBefore: String? = nil,
        contextAfter: String? = nil,
        fractionInChapter: Double = 0
    ) {
        self.stableBlockID = stableBlockID
        self.textQuote = textQuote
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.fractionInChapter = fractionInChapter.clamped(to: 0...1)
    }

    init(progress: ReadingProgress) {
        self.init(
            stableBlockID: progress.stableBlockID,
            textQuote: progress.textQuote,
            contextBefore: progress.contextBefore,
            contextAfter: progress.contextAfter,
            fractionInChapter: progress.fractionInChapter ?? 0
        )
    }

    init(bookmark: Bookmark) {
        self.init(
            stableBlockID: bookmark.stableBlockID,
            textQuote: bookmark.textQuote,
            contextBefore: bookmark.contextBefore,
            contextAfter: bookmark.contextAfter,
            fractionInChapter: bookmark.fractionInChapter ?? 0
        )
    }
}

nonisolated struct ReaderLocationCapture: Equatable, Sendable {
    let stableBlockID: String?
    let fractionInChapter: Double

    init(stableBlockID: String?, fractionInChapter: Double) {
        self.stableBlockID = stableBlockID
        self.fractionInChapter = fractionInChapter.clamped(to: 0...1)
    }
}

nonisolated enum ReaderAnchorResolutionStrategy: Equatable, Sendable {
    case stableBlock
    case textQuote
    case nearbyContext
    case fraction
}

nonisolated struct ReaderResolvedLocation: Equatable, Sendable {
    let stableBlockID: String?
    let fractionInChapter: Double
    let strategy: ReaderAnchorResolutionStrategy
}

nonisolated enum ReaderSemanticAnchor {
    private static let quoteLimit = 220
    private static let contextLimit = 120

    static func make(
        from capture: ReaderLocationCapture,
        blocks: [MarkdownRenderedBlock]
    ) -> ReaderLocationAnchor {
        guard let stableBlockID = capture.stableBlockID,
              let index = blocks.firstIndex(where: { $0.id == stableBlockID }) else {
            return ReaderLocationAnchor(fractionInChapter: capture.fractionInChapter)
        }

        let quote = shortened(blocks[index].normalizedText, limit: quoteLimit, fromEnd: false)
        let previousText = nearestNonemptyText(before: index, in: blocks)
        let nextText = nearestNonemptyText(after: index, in: blocks)
        return ReaderLocationAnchor(
            stableBlockID: stableBlockID,
            textQuote: optional(quote),
            contextBefore: optional(shortened(previousText, limit: contextLimit, fromEnd: true)),
            contextAfter: optional(shortened(nextText, limit: contextLimit, fromEnd: false)),
            fractionInChapter: capture.fractionInChapter
        )
    }

    static func resolve(
        _ anchor: ReaderLocationAnchor,
        in blocks: [MarkdownRenderedBlock]
    ) -> ReaderResolvedLocation {
        let fraction = anchor.fractionInChapter.clamped(to: 0...1)
        if let stableBlockID = anchor.stableBlockID,
           blocks.contains(where: { $0.id == stableBlockID }) {
            return ReaderResolvedLocation(
                stableBlockID: stableBlockID,
                fractionInChapter: fraction,
                strategy: .stableBlock
            )
        }

        if let index = bestQuoteMatch(for: anchor, in: blocks) {
            return ReaderResolvedLocation(
                stableBlockID: blocks[index].id,
                fractionInChapter: fraction,
                strategy: .textQuote
            )
        }

        if let index = contextFallbackIndex(for: anchor, in: blocks) {
            return ReaderResolvedLocation(
                stableBlockID: blocks[index].id,
                fractionInChapter: fraction,
                strategy: .nearbyContext
            )
        }

        return ReaderResolvedLocation(
            stableBlockID: nil,
            fractionInChapter: fraction,
            strategy: .fraction
        )
    }

    private static func bestQuoteMatch(
        for anchor: ReaderLocationAnchor,
        in blocks: [MarkdownRenderedBlock]
    ) -> Int? {
        guard let quote = optional(normalized(anchor.textQuote)), !blocks.isEmpty else { return nil }
        let expectedIndex = Int((Double(blocks.count - 1) * anchor.fractionInChapter).rounded())
        var best: (index: Int, score: Int, distance: Int)?

        for index in blocks.indices {
            let text = blocks[index].normalizedText
            let quoteScore: Int
            if text == quote {
                quoteScore = 100
            } else if text.contains(quote) || quote.contains(text), !text.isEmpty {
                quoteScore = 80
            } else {
                continue
            }

            var score = quoteScore
            if contextMatches(anchor.contextBefore, nearestNonemptyText(before: index, in: blocks)) {
                score += 10
            }
            if contextMatches(anchor.contextAfter, nearestNonemptyText(after: index, in: blocks)) {
                score += 10
            }
            let candidate = (index: index, score: score, distance: abs(index - expectedIndex))
            if best == nil
                || candidate.score > best!.score
                || (candidate.score == best!.score && candidate.distance < best!.distance) {
                best = candidate
            }
        }
        return best?.index
    }

    private static func contextFallbackIndex(
        for anchor: ReaderLocationAnchor,
        in blocks: [MarkdownRenderedBlock]
    ) -> Int? {
        if let after = optional(normalized(anchor.contextAfter)),
           let index = blocks.firstIndex(where: { contextMatches(after, $0.normalizedText) }) {
            return index
        }
        if let before = optional(normalized(anchor.contextBefore)),
           let index = blocks.lastIndex(where: { contextMatches(before, $0.normalizedText) }) {
            return nextNonemptyIndex(after: index, in: blocks) ?? index
        }
        return nil
    }

    private static func nearestNonemptyText(
        before index: Int,
        in blocks: [MarkdownRenderedBlock]
    ) -> String {
        guard index > blocks.startIndex else { return "" }
        for candidateIndex in blocks[..<index].indices.reversed() {
            let text = blocks[candidateIndex].normalizedText
            if !text.isEmpty { return text }
        }
        return ""
    }

    private static func nearestNonemptyText(
        after index: Int,
        in blocks: [MarkdownRenderedBlock]
    ) -> String {
        guard index < blocks.index(before: blocks.endIndex) else { return "" }
        for candidateIndex in blocks.index(after: index)..<blocks.endIndex {
            let text = blocks[candidateIndex].normalizedText
            if !text.isEmpty { return text }
        }
        return ""
    }

    private static func nextNonemptyIndex(
        after index: Int,
        in blocks: [MarkdownRenderedBlock]
    ) -> Int? {
        guard index < blocks.index(before: blocks.endIndex) else { return nil }
        return (blocks.index(after: index)..<blocks.endIndex).first {
            !blocks[$0].normalizedText.isEmpty
        }
    }

    private static func contextMatches(_ stored: String?, _ candidate: String) -> Bool {
        guard let stored = optional(normalized(stored)), !candidate.isEmpty else { return false }
        return contextMatches(stored, candidate)
    }

    private static func contextMatches(_ stored: String, _ candidate: String) -> Bool {
        candidate == stored || candidate.contains(stored) || stored.contains(candidate)
    }

    private static func normalized(_ value: String?) -> String {
        value?
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ") ?? ""
    }

    private static func shortened(_ value: String, limit: Int, fromEnd: Bool) -> String {
        guard value.count > limit else { return value }
        return fromEnd ? String(value.suffix(limit)) : String(value.prefix(limit))
    }

    private static func optional(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}

nonisolated enum ReaderProgressCalculator {
    static func overallProgress(
        chapterIndex: Int,
        chapterCount: Int,
        fractionInChapter: Double
    ) -> Double {
        guard chapterCount > 0 else { return 0 }
        let safeIndex = min(max(chapterIndex, 0), chapterCount - 1)
        let fraction = fractionInChapter.clamped(to: 0...1)
        return ((Double(safeIndex) + fraction) / Double(chapterCount)).clamped(to: 0...1)
    }

    static func chapterIndex(for overallProgress: Double, chapterCount: Int) -> Int? {
        guard chapterCount > 0 else { return nil }
        return min(
            Int((overallProgress.clamped(to: 0...1) * Double(chapterCount)).rounded(.down)),
            chapterCount - 1
        )
    }
}

nonisolated struct ReaderBookmarkNavigation: Identifiable, Equatable, Sendable {
    let id = UUID()
    let chapterID: Chapter.ID
    let anchor: ReaderLocationAnchor
}

nonisolated struct ReaderResolvedNavigation: Identifiable, Equatable, Sendable {
    let id: UUID
    let location: ReaderResolvedLocation
}

nonisolated private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
