import Foundation
import GRDB
import Testing
@testable import iEvelyn

@Suite("Chapter content foundations", .serialized)
struct ChapterContentFoundationTests {
    private let referenceDate = Date(timeIntervalSince1970: 2_100_100_000)

    @Test("Repository saves canonical Markdown with optimistic revision checks")
    func repositorySaveAndConflict() async throws {
        let repository = GRDBLibraryRepository(database: try LibraryDatabase.makeInMemory())
        let bookID = try await repository.createBook(
            metadata: BookMetadataInput(title: "Editor Fixture", authors: ["Test Author"]),
            at: referenceDate
        )
        let chapterID = try await repository.createChapter(
            bookID: bookID,
            title: "Opening",
            at: referenceDate
        )
        try await repository.database.write { database in
            guard var chapter = try Chapter.fetchOne(database, key: chapterID.databaseString) else {
                throw ChapterContentFoundationTestError.missingFixture
            }
            chapter.sourceHash = "old-derived-hash"
            try chapter.update(database)
        }

        let saved = try await repository.updateChapterMarkdown(
            id: chapterID,
            markdown: "# Opening\n\nCanonical **Markdown**.",
            expectedRenderRevision: 0,
            at: referenceDate.addingTimeInterval(10)
        )
        #expect(saved.renderRevision == 1)
        #expect(saved.sourceHash == nil)
        #expect(saved.markdown == "# Opening\n\nCanonical **Markdown**.")

        do {
            _ = try await repository.updateChapterMarkdown(
                id: chapterID,
                markdown: "Stale replacement",
                expectedRenderRevision: 0,
                at: referenceDate.addingTimeInterval(20)
            )
            Issue.record("Expected a stale chapter revision to be rejected")
        } catch let conflict as ChapterRevisionConflict {
            #expect(conflict.storedChapter == saved)
        }

        let stored = try #require(try await repository.chapters(forBookID: bookID).first)
        #expect(stored.markdown == saved.markdown)
        #expect(stored.renderRevision == 1)

        try await repository.moveBookToTrash(
            id: bookID,
            at: referenceDate.addingTimeInterval(30)
        )
        do {
            _ = try await repository.updateChapterMarkdown(
                id: chapterID,
                markdown: "Trash must stay read-only",
                expectedRenderRevision: 1,
                at: referenceDate.addingTimeInterval(40)
            )
            Issue.record("Expected an update to a trashed book to be rejected")
        } catch let error as LibraryRepositoryError {
            #expect(error == .bookIsInTrash)
        }
    }

    @Test("Metrics count Unicode words and user-perceived characters")
    func textMetrics() {
        let markdown = "Hello, 世界! Evelyn’s café. 👩🏽‍💻"
        let metrics = ChapterTextMetrics(markdown: markdown)

        #expect(metrics.wordCount == 4)
        #expect(metrics.characterCount == markdown.count)
        #expect(ChapterTextMetrics.zero == ChapterTextMetrics(markdown: ""))
    }

    @Test("Importer accepts UTF-8 Markdown and text while rejecting invalid input")
    func sourceImporter() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                Issue.record("Could not remove the temporary import fixture: \(error)")
            }
        }

        let markdownURL = directory.appending(path: "chapter.md")
        var markdownData = Data([0xef, 0xbb, 0xbf])
        markdownData.append(Data("# 章节\n\nUnicode café".utf8))
        try markdownData.write(to: markdownURL)

        let invalidURL = directory.appending(path: "invalid.txt")
        try Data([0xff, 0xfe, 0x00]).write(to: invalidURL)

        let unsupportedURL = directory.appending(path: "chapter.rtf")
        try Data("text".utf8).write(to: unsupportedURL)

        let importer = ChapterSourceImporter()
        #expect(try await importer.loadUTF8Text(from: markdownURL) == "# 章节\n\nUnicode café")
        await expectImportError(.invalidUTF8) {
            _ = try await importer.loadUTF8Text(from: invalidURL)
        }
        await expectImportError(.unsupportedFileType) {
            _ = try await importer.loadUTF8Text(from: unsupportedURL)
        }
    }

    private func expectImportError(
        _ expected: ChapterSourceImportError,
        operation: () async throws -> Void,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        do {
            try await operation()
            Issue.record("Expected chapter source import to fail", sourceLocation: sourceLocation)
        } catch let error as ChapterSourceImportError {
            #expect(error == expected, sourceLocation: sourceLocation)
        } catch {
            Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation)
        }
    }
}

private nonisolated enum ChapterContentFoundationTestError: Error {
    case missingFixture
}
