import Foundation

nonisolated protocol BookContentImporting: Sendable {
    func loadCompleteBook(from sourceURL: URL) async throws -> CompleteBookContent
    func loadAppendedChapters(from sourceURL: URL) async throws -> [ImportedBookChapter]
}

nonisolated struct CompleteBookContent: Equatable, Sendable {
    let title: String
    let authors: [String]
    let chapters: [ImportedBookChapter]

    func validateMetadata(_ metadata: ValidatedBookMetadata) throws {
        guard LibraryNameNormalizer.normalize(title) == LibraryNameNormalizer.normalize(metadata.title) else {
            throw BookContentImportError.titleMismatch(fileTitle: title, enteredTitle: metadata.title)
        }

        let fileAuthors = authors.map(LibraryNameNormalizer.normalize)
        let enteredAuthors = metadata.authors.map(LibraryNameNormalizer.normalize)
        guard fileAuthors == enteredAuthors else {
            throw BookContentImportError.authorsMismatch(
                fileAuthors: authors,
                enteredAuthors: metadata.authors
            )
        }
    }
}

nonisolated enum BookContentImportError: LocalizedError, Equatable {
    case contentFileRequired
    case missingBookTitle
    case missingAuthor
    case emptyBookContent
    case appendMustStartWithChapter
    case appendContainsBookMetadata
    case chapterTitleRequired
    case titleMismatch(fileTitle: String, enteredTitle: String)
    case authorsMismatch(fileAuthors: [String], enteredAuthors: [String])

    var errorDescription: String? {
        switch self {
        case .contentFileRequired:
            "Choose a UTF-8 Markdown or text content file."
        case .missingBookTitle:
            "A replacement content file must start with a level-1 book title, such as “# Book Title”."
        case .missingAuthor:
            "Place at least one level-3 author heading immediately after the book title, such as “### Author Name” or “### Author: Author Name”."
        case .emptyBookContent:
            "The selected file does not contain any book content."
        case .appendMustStartWithChapter:
            "An appended content file must start with a level-2 chapter heading, such as “## Chapter Title”."
        case .appendContainsBookMetadata:
            "An appended content file must contain chapters only, without a level-1 book title or author preamble."
        case .chapterTitleRequired:
            "Every level-2 chapter heading must include a title."
        case .titleMismatch(let fileTitle, let enteredTitle):
            "The content file title “\(fileTitle)” does not match the entered title “\(enteredTitle)”."
        case .authorsMismatch(let fileAuthors, let enteredAuthors):
            "The content file authors (\(fileAuthors.joined(separator: ", "))) do not match the entered authors (\(enteredAuthors.joined(separator: ", ")))."
        }
    }
}

actor BookContentImporter: BookContentImporting {
    private let sourceImporter: any ChapterSourceImporting
    private let parser: BookContentParser

    init(
        sourceImporter: any ChapterSourceImporting = ChapterSourceImporter(),
        parser: BookContentParser = BookContentParser()
    ) {
        self.sourceImporter = sourceImporter
        self.parser = parser
    }

    func loadCompleteBook(from sourceURL: URL) async throws -> CompleteBookContent {
        let source = try await sourceImporter.loadUTF8Text(from: sourceURL)
        try Task.checkCancellation()
        return try parser.parseCompleteBook(source)
    }

    func loadAppendedChapters(from sourceURL: URL) async throws -> [ImportedBookChapter] {
        let source = try await sourceImporter.loadUTF8Text(from: sourceURL)
        try Task.checkCancellation()
        return try parser.parseAppendedChapters(source)
    }
}

nonisolated struct BookContentParser: Sendable {
    func parseCompleteBook(_ source: String) throws -> CompleteBookContent {
        let normalizedSource = normalizeLineEndings(source)
        let lines = normalizedSource.components(separatedBy: "\n")
        guard let titleLineIndex = firstNonblankLineIndex(in: lines),
              let title = headingText(in: lines[titleLineIndex], level: 1) else {
            throw BookContentImportError.missingBookTitle
        }
        guard !title.isEmpty else {
            throw BookContentImportError.missingBookTitle
        }

        var authors: [String] = []
        var cursor = titleLineIndex + 1
        while cursor < lines.count {
            while cursor < lines.count, lines[cursor].trimmingCharacters(in: .whitespaces).isEmpty {
                cursor += 1
            }
            guard cursor < lines.count,
                  let rawAuthor = headingText(in: lines[cursor], level: 3) else {
                break
            }
            let author = normalizedAuthor(rawAuthor)
            guard !author.isEmpty else {
                throw BookContentImportError.missingAuthor
            }
            authors.append(author)
            cursor += 1
        }
        guard !authors.isEmpty else {
            throw BookContentImportError.missingAuthor
        }

        let chapterHeadings = levelTwoHeadings(in: lines)
        let chapters: [ImportedBookChapter]
        if chapterHeadings.isEmpty {
            guard containsContent(after: cursor, in: lines) else {
                throw BookContentImportError.emptyBookContent
            }
            chapters = [
                ImportedBookChapter(
                    title: title,
                    markdown: lines[cursor...]
                        .joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
            ]
        } else {
            chapters = try makeChapters(
                lines: lines,
                headings: chapterHeadings,
                firstSectionStart: cursor
            )
        }

        return CompleteBookContent(title: title, authors: authors, chapters: chapters)
    }

    func parseAppendedChapters(_ source: String) throws -> [ImportedBookChapter] {
        let normalizedSource = normalizeLineEndings(source)
        let lines = normalizedSource.components(separatedBy: "\n")
        guard let firstLineIndex = firstNonblankLineIndex(in: lines) else {
            throw BookContentImportError.emptyBookContent
        }
        if headingText(in: lines[firstLineIndex], level: 1) != nil
            || headingText(in: lines[firstLineIndex], level: 3) != nil {
            throw BookContentImportError.appendContainsBookMetadata
        }
        guard headingText(in: lines[firstLineIndex], level: 2) != nil else {
            throw BookContentImportError.appendMustStartWithChapter
        }

        let chapterHeadings = levelTwoHeadings(in: lines)
        guard chapterHeadings.first?.index == firstLineIndex else {
            throw BookContentImportError.appendMustStartWithChapter
        }
        return try makeChapters(
            lines: lines,
            headings: chapterHeadings,
            firstSectionStart: firstLineIndex
        )
    }

    private func makeChapters(
        lines: [String],
        headings: [(index: Int, title: String)],
        firstSectionStart: Int
    ) throws -> [ImportedBookChapter] {
        try headings.enumerated().map { offset, heading in
            guard !heading.title.isEmpty else {
                throw BookContentImportError.chapterTitleRequired
            }
            let start = offset == 0 ? firstSectionStart : heading.index
            let end = offset + 1 < headings.count ? headings[offset + 1].index : lines.count
            let markdown = lines[start..<end]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return ImportedBookChapter(title: heading.title, markdown: markdown)
        }
    }

    private func levelTwoHeadings(in lines: [String]) -> [(index: Int, title: String)] {
        var headings: [(index: Int, title: String)] = []
        var fence: MarkdownFence?

        for (index, line) in lines.enumerated() {
            if let activeFence = fence {
                if activeFence.closes(with: line) {
                    fence = nil
                }
                continue
            }
            if let openingFence = MarkdownFence(opening: line) {
                fence = openingFence
                continue
            }
            if let title = headingText(in: line, level: 2) {
                headings.append((index, title))
            }
        }
        return headings
    }

    private func headingText(in line: String, level: Int) -> String? {
        let line = line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        let prefix = String(repeating: "#", count: level)
        guard line.hasPrefix(prefix) else { return nil }
        let boundaryIndex = line.index(line.startIndex, offsetBy: level)
        guard boundaryIndex < line.endIndex,
              line[boundaryIndex] == " " || line[boundaryIndex] == "\t" else {
            return nil
        }
        guard level == 6 || line.index(after: boundaryIndex) == line.endIndex
                || line[line.index(after: boundaryIndex)] != "#" else {
            return nil
        }

        var text = String(line[line.index(after: boundaryIndex)...])
            .trimmingCharacters(in: .whitespaces)
        if let hashStart = text.range(of: #"\s+#+\s*$"#, options: .regularExpression) {
            text.removeSubrange(hashStart)
            text = text.trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    private func normalizedAuthor(_ rawAuthor: String) -> String {
        let trimmed = rawAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased(with: Locale(identifier: "en_US_POSIX"))
        for prefix in ["author:", "authors:", "作者：", "作者:"] where lowered.hasPrefix(prefix) {
            let index = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
            return String(trimmed[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func firstNonblankLineIndex(in lines: [String]) -> Int? {
        lines.firstIndex { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func containsContent(after index: Int, in lines: [String]) -> Bool {
        guard index < lines.count else { return false }
        return lines[index...].contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func normalizeLineEndings(_ source: String) -> String {
        source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

private nonisolated struct MarkdownFence: Sendable {
    let marker: Character
    let count: Int

    init?(opening line: String) {
        let candidate = line.drop(while: { $0 == " " })
        guard line.count - candidate.count <= 3,
              let marker = candidate.first,
              marker == "`" || marker == "~" else {
            return nil
        }
        let count = candidate.prefix(while: { $0 == marker }).count
        guard count >= 3 else { return nil }
        self.marker = marker
        self.count = count
    }

    func closes(with line: String) -> Bool {
        let candidate = line.drop(while: { $0 == " " })
        guard line.count - candidate.count <= 3 else { return false }
        let markerCount = candidate.prefix(while: { $0 == marker }).count
        guard markerCount >= count else { return false }
        return candidate.dropFirst(markerCount).allSatisfy { $0 == " " || $0 == "\t" || $0 == "\r" }
    }
}
