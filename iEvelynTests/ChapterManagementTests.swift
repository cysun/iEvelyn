import Foundation
import GRDB
import Testing
@testable import iEvelyn

@Suite("Chapter management", .serialized)
struct ChapterManagementTests {
    private let referenceDate = Date(timeIntervalSince1970: 2_100_000_000)

    @Test("Chapter titles and Unicode word summaries are deterministic")
    func validationAndWordCounts() throws {
        #expect(try ChapterTitleInput(title: "  Opening  ").validated() == "Opening")
        do {
            _ = try ChapterTitleInput(title: " \n ").validated()
            Issue.record("Expected an empty chapter title to fail validation")
        } catch let error as ChapterValidationError {
            #expect(error == .titleRequired)
        }

        let first = Chapter(
            bookID: UUID(),
            title: "First",
            markdown: "Hello, world! It's Evelyn’s 2026.",
            position: 0
        )
        let second = Chapter(
            bookID: first.bookID,
            title: "Second",
            markdown: "Unicode 章节 works",
            position: 1
        )
        let summary = ChapterCollectionSummary(chapters: [first, second])

        #expect(first.wordCount == 5)
        #expect(second.wordCount == 3)
        #expect(summary == ChapterCollectionSummary(chapters: [first, second]))
        #expect(summary.chapterCount == 2)
        #expect(summary.wordCount == 8)
        #expect(ChapterCollectionSummary(chapters: []).chapterCount == 0)
        #expect(ChapterCollectionSummary(chapters: []).wordCount == 0)
    }

    @Test("Create, rename, and duplicate preserve identities and permit duplicate titles")
    func createRenameAndDuplicate() async throws {
        let repository = try makeRepository()
        let bookID = try await makeBook(in: repository)
        let openingID = try await repository.createChapter(
            bookID: bookID,
            title: " Opening ",
            at: referenceDate
        )
        let secondOpeningID = try await repository.createChapter(
            bookID: bookID,
            title: "Opening",
            at: referenceDate.addingTimeInterval(10)
        )

        try await repository.database.write { database in
            guard var opening = try Chapter.fetchOne(database, key: openingID.databaseString) else {
                throw ChapterTestError.missingFixture
            }
            opening.markdown = "Original chapter body"
            opening.renderRevision = 3
            opening.sourceHash = "source-hash"
            try opening.update(database)
        }

        try await repository.renameChapter(
            id: secondOpeningID,
            title: "  Revised  ",
            at: referenceDate.addingTimeInterval(20)
        )
        let duplicateID = try await repository.duplicateChapter(
            id: openingID,
            at: referenceDate.addingTimeInterval(30)
        )
        let chapters = try await repository.chapters(forBookID: bookID)

        #expect(Set(chapters.map(\.id)).count == 3)
        #expect(chapters.map(\.id) == [openingID, duplicateID, secondOpeningID])
        #expect(chapters.map(\.position) == [0, 1, 2])
        #expect(chapters.map(\.title) == ["Opening", "Opening", "Revised"])
        #expect(chapters[0].id == openingID)
        #expect(chapters[1].id == duplicateID)
        #expect(chapters[1].markdown == "Original chapter body")
        #expect(chapters[1].renderRevision == 3)
        #expect(chapters[1].sourceHash == "source-hash")
    }

    @Test("Reorder is transactional and keeps stable UUIDs")
    func reorderIsTransactional() async throws {
        let repository = try makeRepository()
        let bookID = try await makeBook(in: repository)
        let firstID = try await repository.createChapter(bookID: bookID, title: "First", at: referenceDate)
        let secondID = try await repository.createChapter(bookID: bookID, title: "Second", at: referenceDate)
        let thirdID = try await repository.createChapter(bookID: bookID, title: "Third", at: referenceDate)

        try await repository.reorderChapters(
            bookID: bookID,
            orderedChapterIDs: [thirdID, firstID, secondID],
            at: referenceDate.addingTimeInterval(60)
        )
        var chapters = try await repository.chapters(forBookID: bookID)
        #expect(chapters.map(\.id) == [thirdID, firstID, secondID])
        #expect(chapters.map(\.position) == [0, 1, 2])

        await expectRepositoryError(.chapterOrderDoesNotMatchBook) {
            try await repository.reorderChapters(
                bookID: bookID,
                orderedChapterIDs: [firstID, secondID],
                at: referenceDate.addingTimeInterval(70)
            )
        }
        chapters = try await repository.chapters(forBookID: bookID)
        #expect(chapters.map(\.id) == [thirdID, firstID, secondID])
        #expect(Set(chapters.map(\.id)) == Set([firstID, secondID, thirdID]))
    }

    @Test("Delete and undo restore content, order, stable identity, and chapter links")
    func deleteAndUndoRestoreChapterLinks() async throws {
        let repository = try makeRepository()
        let bookID = try await makeBook(in: repository)
        let firstID = try await repository.createChapter(bookID: bookID, title: "First", at: referenceDate)
        let middleID = try await repository.createChapter(bookID: bookID, title: "Middle", at: referenceDate)
        let lastID = try await repository.createChapter(bookID: bookID, title: "Last", at: referenceDate)

        let asset = Asset(
            bookID: bookID,
            chapterID: middleID,
            purpose: .chapterImage,
            mediaType: "image/png",
            storageRelativePath: "Books/\(bookID.databaseString)/middle.png",
            checksum: "fixture-checksum",
            byteCount: 42,
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
        let bookmark = Bookmark(
            bookID: bookID,
            chapterID: middleID,
            label: "Middle mark",
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
        try await repository.insertAsset(asset)
        try await repository.insertReadingProgress(
            ReadingProgress(
                bookID: bookID,
                chapterID: middleID,
                stableBlockID: nil,
                textQuote: nil,
                contextBefore: nil,
                contextAfter: nil,
                fractionInChapter: nil,
                overallProgress: 0.5,
                lastReadAt: referenceDate
            )
        )
        try await repository.insertBookmark(bookmark)

        let deletion = try await repository.deleteChapter(
            id: middleID,
            at: referenceDate.addingTimeInterval(30)
        )
        #expect(deletion.chapter.id == middleID)
        #expect(deletion.linkedAssetIDs == [asset.id])
        #expect(deletion.hadLinkedReadingProgress)
        #expect(deletion.linkedBookmarkIDs == [bookmark.id])
        #expect(try await repository.chapters(forBookID: bookID).map(\.id) == [firstID, lastID])
        #expect(try await repository.chapters(forBookID: bookID).map(\.position) == [0, 1])

        let clearedLinks = try await fetchLinks(repository: repository, assetID: asset.id, bookmarkID: bookmark.id, bookID: bookID)
        #expect(clearedLinks == ChapterLinkState(assetChapterID: nil, progressChapterID: nil, bookmarkChapterID: nil))

        try await repository.restoreChapterDeletion(
            deletion,
            at: referenceDate.addingTimeInterval(40)
        )
        let restored = try await repository.chapters(forBookID: bookID)
        #expect(restored.map(\.id) == [firstID, middleID, lastID])
        #expect(restored.map(\.position) == [0, 1, 2])
        #expect(restored[1].title == "Middle")

        let restoredLinks = try await fetchLinks(repository: repository, assetID: asset.id, bookmarkID: bookmark.id, bookID: bookID)
        #expect(restoredLinks == ChapterLinkState(
            assetChapterID: middleID,
            progressChapterID: middleID,
            bookmarkChapterID: middleID
        ))
    }

    @Test("Trashed books reject chapter mutations")
    func trashedBooksAreReadOnly() async throws {
        let repository = try makeRepository()
        let bookID = try await makeBook(in: repository)
        try await repository.moveBookToTrash(id: bookID, at: referenceDate)

        await expectRepositoryError(.bookIsInTrash) {
            _ = try await repository.createChapter(
                bookID: bookID,
                title: "Not Allowed",
                at: referenceDate
            )
        }
        #expect(try await repository.chapters(forBookID: bookID).isEmpty)
    }

    private func makeRepository() throws -> GRDBLibraryRepository {
        GRDBLibraryRepository(database: try LibraryDatabase.makeInMemory())
    }

    private func makeBook(in repository: GRDBLibraryRepository) async throws -> UUID {
        try await repository.createBook(
            metadata: BookMetadataInput(title: "Chapter Fixture", authors: ["Test Author"]),
            at: referenceDate
        )
    }

    private func fetchLinks(
        repository: GRDBLibraryRepository,
        assetID: UUID,
        bookmarkID: UUID,
        bookID: UUID
    ) async throws -> ChapterLinkState {
        try await repository.database.read { database in
            let asset = try Asset.fetchOne(database, key: assetID.databaseString)
            let progress = try ReadingProgress.fetchOne(database, key: bookID.databaseString)
            let bookmark = try Bookmark.fetchOne(database, key: bookmarkID.databaseString)
            return ChapterLinkState(
                assetChapterID: asset?.chapterID,
                progressChapterID: progress?.chapterID,
                bookmarkChapterID: bookmark?.chapterID
            )
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

private nonisolated struct ChapterLinkState: Equatable, Sendable {
    let assetChapterID: UUID?
    let progressChapterID: UUID?
    let bookmarkChapterID: UUID?
}

private nonisolated enum ChapterTestError: Error {
    case missingFixture
}
