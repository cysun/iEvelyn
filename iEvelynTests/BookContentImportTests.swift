import Foundation
import Testing
@testable import iEvelyn

@Suite("Whole-book content import", .serialized)
struct BookContentImportTests {
    private let referenceDate = Date(timeIntervalSince1970: 2_200_000_000)
    private let parser = BookContentParser()

    @Test("Complete files accept English, Chinese, and bare author headings")
    func completeFileAuthorHeadings() throws {
        let english = try parser.parseCompleteBook(
            """
            # English Book
            ### Author: First Author
            ### Authors: Second Author

            ## Opening

            First body.
            """
        )
        #expect(english.title == "English Book")
        #expect(english.authors == ["First Author", "Second Author"])
        #expect(english.chapters.map(\.title) == ["Opening"])
        #expect(english.chapters[0].markdown == "## Opening\n\nFirst body.")

        let chinese = try parser.parseCompleteBook(
            """
            # 毫末生
            ### 作者：蛋伤

            ## 楔子

            正文。
            """
        )
        #expect(chinese.title == "毫末生")
        #expect(chinese.authors == ["蛋伤"])
        #expect(chinese.chapters.map(\.title) == ["楔子"])

        let bare = try parser.parseCompleteBook(
            """
            # Bare Heading
            ### Writer Name

            Body without chapter headings.
            """
        )
        #expect(bare.authors == ["Writer Name"])
        #expect(bare.chapters.map(\.title) == ["Bare Heading"])
        #expect(bare.chapters[0].markdown == "Body without chapter headings.")
    }

    @Test("Level-2 headings split chapters while fenced examples remain content")
    func chapterSplittingIgnoresFencedHeadings() throws {
        let content = try parser.parseCompleteBook(
            """
            # Parser Book
            ### Author: Test Author

            ## Opening

            ```markdown
            ## This is an example, not a chapter
            ```

            ## Ending

            Done.
            """
        )

        #expect(content.chapters.map(\.title) == ["Opening", "Ending"])
        #expect(content.chapters[0].markdown.contains("This is an example, not a chapter"))
        #expect(content.chapters[1].markdown == "## Ending\n\nDone.")
    }

    @Test("Append files require chapter-only level-2 sections")
    func appendFileValidation() throws {
        let chapters = try parser.parseAppendedChapters(
            """

            ## Third Chapter

            Third body.

            ## Fourth Chapter

            Fourth body.
            """
        )
        #expect(chapters.map(\.title) == ["Third Chapter", "Fourth Chapter"])
        #expect(chapters[0].markdown == "## Third Chapter\n\nThird body.")

        expectImportError(.appendContainsBookMetadata) {
            try parser.parseAppendedChapters("# Complete Book\n### Author: Someone\n## Chapter\nBody")
        }
        expectImportError(.appendMustStartWithChapter) {
            try parser.parseAppendedChapters("Introductory text\n## Chapter\nBody")
        }
    }

    @Test("Complete-file metadata must match the form")
    func metadataMustMatchForm() throws {
        let content = try parser.parseCompleteBook(
            "# File Title\n### 作者：File Author\n\nBook body."
        )

        expectImportError(.titleMismatch(fileTitle: "File Title", enteredTitle: "Other Title")) {
            try content.validateMetadata(
                BookMetadataInput(title: "Other Title", authors: ["File Author"]).validated()
            )
        }
        expectImportError(
            .authorsMismatch(fileAuthors: ["File Author"], enteredAuthors: ["Other Author"])
        ) {
            try content.validateMetadata(
                BookMetadataInput(title: "File Title", authors: ["Other Author"]).validated()
            )
        }
    }

    @Test("Atomic create stores metadata and ordered imported chapters")
    func atomicCreate() async throws {
        let repository = try makeRepository()
        let bookID = try await repository.createBook(
            metadata: BookMetadataInput(
                title: "Imported Book",
                authors: ["First Author", "Second Author"]
            ),
            contentChapters: [
                ImportedBookChapter(title: "Opening", markdown: "## Opening\n\nFirst."),
                ImportedBookChapter(title: "Ending", markdown: "## Ending\n\nLast.")
            ],
            at: referenceDate
        )

        let book = try #require(await repository.fetchBook(id: bookID))
        #expect(book.title == "Imported Book")
        #expect(try await repository.authors(forBookID: bookID).map(\.displayName) == [
            "First Author", "Second Author"
        ])
        let chapters = try await repository.chapters(forBookID: bookID)
        #expect(chapters.map(\.title) == ["Opening", "Ending"])
        #expect(chapters.map(\.position) == [0, 1])
        #expect(chapters.map(\.markdown) == ["## Opening\n\nFirst.", "## Ending\n\nLast."])
    }

    @Test("Replace preserves deterministic chapter identities and append adds to the end")
    func replaceAndAppend() async throws {
        let repository = try makeRepository()
        let bookID = try await repository.createBook(
            metadata: BookMetadataInput(title: "Update Book", authors: ["Test Author"]),
            contentChapters: [
                ImportedBookChapter(title: "Opening", markdown: "## Opening\n\nOld."),
                ImportedBookChapter(title: "Middle", markdown: "## Middle\n\nRemove me."),
                ImportedBookChapter(title: "Ending", markdown: "## Ending\n\nKeep me.")
            ],
            at: referenceDate
        )
        let original = try await repository.chapters(forBookID: bookID)

        try await repository.updateBook(
            id: bookID,
            metadata: BookMetadataInput(title: "Updated Book", authors: ["Test Author"]),
            chapterUpdate: .replace([
                ImportedBookChapter(title: "Opening", markdown: "## Opening\n\nRevised."),
                ImportedBookChapter(title: "Ending", markdown: "## Ending\n\nKeep me."),
                ImportedBookChapter(title: "New Chapter", markdown: "## New Chapter\n\nNew.")
            ]),
            at: referenceDate.addingTimeInterval(10)
        )

        var chapters = try await repository.chapters(forBookID: bookID)
        #expect(chapters.map(\.title) == ["Opening", "Ending", "New Chapter"])
        #expect(chapters[0].id == original[0].id)
        #expect(chapters[0].renderRevision == original[0].renderRevision + 1)
        #expect(chapters[1].id == original[2].id)
        #expect(!chapters.map(\.id).contains(original[1].id))

        try await repository.updateBook(
            id: bookID,
            metadata: BookMetadataInput(title: "Updated Book", authors: ["Test Author"]),
            chapterUpdate: .append([
                ImportedBookChapter(title: "Appendix", markdown: "## Appendix\n\nExtra.")
            ]),
            at: referenceDate.addingTimeInterval(20)
        )

        chapters = try await repository.chapters(forBookID: bookID)
        #expect(chapters.map(\.title) == ["Opening", "Ending", "New Chapter", "Appendix"])
        #expect(chapters.map(\.position) == [0, 1, 2, 3])
    }

    @Test("Invalid imported chapters do not partially update a book")
    func invalidUpdateRollsBack() async throws {
        let repository = try makeRepository()
        let bookID = try await repository.createBook(
            metadata: BookMetadataInput(title: "Original", authors: ["Original Author"]),
            contentChapters: [
                ImportedBookChapter(title: "Opening", markdown: "## Opening\n\nOriginal.")
            ],
            at: referenceDate
        )

        await expectRepositoryError(.bookContentRequired) {
            try await repository.updateBook(
                id: bookID,
                metadata: BookMetadataInput(title: "Changed", authors: ["Changed Author"]),
                chapterUpdate: .replace([]),
                at: referenceDate.addingTimeInterval(30)
            )
        }

        let book = try #require(await repository.fetchBook(id: bookID))
        #expect(book.title == "Original")
        #expect(try await repository.authors(forBookID: bookID).map(\.displayName) == ["Original Author"])
        #expect(try await repository.chapters(forBookID: bookID).map(\.title) == ["Opening"])
    }

    private func makeRepository() throws -> GRDBLibraryRepository {
        GRDBLibraryRepository(database: try LibraryDatabase.makeInMemory())
    }

    private func expectImportError<T>(
        _ expectedError: BookContentImportError,
        operation: () throws -> T,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            _ = try operation()
            Issue.record("Expected content import to fail", sourceLocation: sourceLocation)
        } catch let error as BookContentImportError {
            #expect(error == expectedError, sourceLocation: sourceLocation)
        } catch {
            Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation)
        }
    }

    private func expectRepositoryError(
        _ expectedError: LibraryRepositoryError,
        operation: () async throws -> Void,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        do {
            try await operation()
            Issue.record("Expected repository operation to fail", sourceLocation: sourceLocation)
        } catch let error as LibraryRepositoryError {
            #expect(error == expectedError, sourceLocation: sourceLocation)
        } catch {
            Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation)
        }
    }
}
