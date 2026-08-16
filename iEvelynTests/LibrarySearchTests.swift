import Foundation
import GRDB
import Testing
@testable import iEvelyn

@Suite("Full-text library search", .serialized)
struct LibrarySearchTests {
    private let referenceDate = Date(timeIntervalSince1970: 2_300_000_000)

    @Test("Chinese metadata, tags, chapter titles, content, punctuation, and snippets are searchable by scope")
    func fieldsUnicodeScopesAndSnippets() async throws {
        let repository = try makeRepository()
        let bookID = try await repository.createBook(
            metadata: BookMetadataInput(
                title: "山海经研究",
                subtitle: "古典奇书",
                authors: ["王小明"],
                tags: ["神话", "先秦"]
            ),
            contentChapters: [
                ImportedBookChapter(
                    title: "北山经",
                    markdown: "## 北山经\n\n精卫填海的故事。\n\n这里也记载「夸父逐日」。"
                )
            ],
            coverSourceURL: nil,
            at: referenceDate
        )

        #expect(try await repository.searchLibrary(
            "山海",
            scope: .titles,
            trashScope: .activeLibrary
        ).map(\.bookID) == [bookID])
        #expect(try await repository.searchLibrary(
            "古典",
            scope: .titles,
            trashScope: .activeLibrary
        ).map(\.bookID) == [bookID])
        #expect(try await repository.searchLibrary(
            "王小",
            scope: .authors,
            trashScope: .activeLibrary
        ).map(\.bookID) == [bookID])
        #expect(try await repository.searchLibrary(
            "神话",
            scope: .tags,
            trashScope: .activeLibrary
        ).map(\.bookID) == [bookID])

        let chapterResults = try await repository.searchLibrary(
            "北山",
            scope: .chapterTitles,
            trashScope: .activeLibrary
        )
        #expect(chapterResults.count == 1)
        #expect(chapterResults[0].chapterTitle == "北山经")

        let contentResults = try await repository.searchLibrary(
            "精卫填海",
            scope: .content,
            trashScope: .activeLibrary
        )
        let contentResult = try #require(contentResults.first)
        #expect(contentResult.bookID == bookID)
        #expect(contentResult.chapterID != nil)
        #expect(contentResult.stableBlockID != nil)
        #expect(contentResult.highlightedSnippet.contains(LibrarySearchIndexer.highlightStart))
        #expect(contentResult.highlightedSnippet.contains("精卫填海"))
        #expect(try await repository.searchLibrary(
            "精卫填海",
            scope: .titles,
            trashScope: .activeLibrary
        ).isEmpty)

        let punctuationResults = try await repository.searchLibrary(
            "「夸父逐日」",
            scope: .content,
            trashScope: .activeLibrary
        )
        #expect(punctuationResults.count == 1)
        #expect(try await repository.searchLibrary(
            "shanhaijing",
            scope: .all,
            trashScope: .activeLibrary
        ).isEmpty)

        try await repository.updateBook(
            id: bookID,
            metadata: BookMetadataInput(
                title: "山海经研究",
                subtitle: "古典奇书",
                authors: ["李小华"],
                tags: ["文学"]
            ),
            at: referenceDate.addingTimeInterval(10)
        )
        #expect(try await repository.searchLibrary(
            "王小明",
            scope: .authors,
            trashScope: .activeLibrary
        ).isEmpty)
        #expect(try await repository.searchLibrary(
            "李小华",
            scope: .authors,
            trashScope: .activeLibrary
        ).map(\.bookID) == [bookID])
        #expect(try await repository.searchLibrary(
            "神话",
            scope: .tags,
            trashScope: .activeLibrary
        ).isEmpty)
        #expect(try await repository.searchLibrary(
            "文学",
            scope: .tags,
            trashScope: .activeLibrary
        ).map(\.bookID) == [bookID])
    }

    @Test("Whole-book replace and append synchronize the index while Trash remains deliberate")
    func replacementAppendTrashAndDeleteSynchronization() async throws {
        let repository = try makeRepository()
        let metadata = BookMetadataInput(title: "更新测试", authors: ["作者甲"])
        let bookID = try await repository.createBook(
            metadata: metadata,
            contentChapters: [
                ImportedBookChapter(title: "旧章", markdown: "## 旧章\n\n旧索引词。")
            ],
            coverSourceURL: nil,
            at: referenceDate
        )
        #expect(try await matches("旧索引词", in: repository).count == 1)

        try await repository.updateBook(
            id: bookID,
            metadata: metadata,
            chapterUpdate: .replace([
                ImportedBookChapter(title: "新章", markdown: "## 新章\n\n替换后的词。")
            ]),
            coverUpdate: .unchanged,
            at: referenceDate.addingTimeInterval(10)
        )
        #expect(try await matches("旧索引词", in: repository).isEmpty)
        #expect(try await matches("替换后的词", in: repository).count == 1)

        try await repository.updateBook(
            id: bookID,
            metadata: metadata,
            chapterUpdate: .append([
                ImportedBookChapter(title: "附录", markdown: "## 附录\n\n追加索引词。")
            ]),
            coverUpdate: .unchanged,
            at: referenceDate.addingTimeInterval(20)
        )
        #expect(try await matches("追加索引词", in: repository).count == 1)

        try await repository.moveBookToTrash(
            id: bookID,
            at: referenceDate.addingTimeInterval(30)
        )
        #expect(try await matches("追加索引词", in: repository).isEmpty)
        #expect(try await repository.searchLibrary(
            "追加索引词",
            scope: .content,
            trashScope: .trash
        ).map(\.bookID) == [bookID])

        try await repository.deleteBookPermanently(id: bookID)
        #expect(try await repository.searchLibrary(
            "追加索引词",
            scope: .content,
            trashScope: .trash
        ).isEmpty)
    }

    @Test("Bookmark labels and notes are never indexed")
    func bookmarkTextIsExcluded() async throws {
        let repository = try makeRepository()
        let bookID = try await repository.createBook(
            metadata: BookMetadataInput(title: "书签测试", authors: ["作者乙"]),
            contentChapters: [
                ImportedBookChapter(title: "正文", markdown: "普通正文。")
            ],
            coverSourceURL: nil,
            at: referenceDate
        )
        let chapterID = try #require(await repository.chapters(forBookID: bookID).first?.id)
        try await repository.insertBookmark(
            Bookmark(
                bookID: bookID,
                chapterID: chapterID,
                label: "PrivateNeedleLabel",
                note: "PrivateNeedleNote"
            )
        )

        #expect(try await repository.searchLibrary(
            "PrivateNeedleLabel",
            scope: .all,
            trashScope: .activeLibrary
        ).isEmpty)
        #expect(try await repository.searchLibrary(
            "PrivateNeedleNote",
            scope: .all,
            trashScope: .activeLibrary
        ).isEmpty)
    }

    @Test("Canonical repair restores deliberately removed search documents")
    func rebuildRepair() async throws {
        let repository = try makeRepository()
        let bookID = try await repository.createBook(
            metadata: BookMetadataInput(title: "修复索引", authors: ["修复者"]),
            contentChapters: [
                ImportedBookChapter(title: "修复章", markdown: "需要重建的正文。")
            ],
            coverSourceURL: nil,
            at: referenceDate
        )
        let originalCount = try await repository.database.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM librarySearchDocuments") ?? 0
        }
        #expect(originalCount > 0)

        try await repository.database.write { database in
            try database.execute(sql: "DELETE FROM librarySearchDocuments")
        }
        #expect(try await matches("需要重建", in: repository).isEmpty)

        let report = try await repository.rebuildSearchIndex()
        #expect(report.previousDocumentCount == 0)
        #expect(report.rebuiltDocumentCount == originalCount)
        #expect(report.indexedBookCount == 1)
        #expect(try await matches("需要重建", in: repository).map(\.bookID) == [bookID])
    }

    @MainActor
    @Test("Author and tag groups expose counts and filter the active library")
    func organizationCountsAndFilters() {
        let first = libraryBook(
            title: "甲书",
            authors: ["共同作者"],
            tags: ["历史"]
        )
        let second = libraryBook(
            title: "乙书",
            authors: ["共同作者", "另一作者"],
            tags: ["历史", "小说"]
        )
        let model = LibraryViewModel(
            repository: PreviewLibraryRepository(books: [first, second]),
            initialBooks: [first, second]
        )

        model.destination = .authors
        let sharedAuthor = model.organizationGroups.first { $0.name == "共同作者" }
        #expect(sharedAuthor?.bookCount == 2)
        model.selectedOrganizationID = sharedAuthor?.id
        #expect(Set(model.visibleBooks.map(\.id)) == [first.id, second.id])

        model.destination = .tags
        let novel = model.organizationGroups.first { $0.name == "小说" }
        #expect(novel?.bookCount == 1)
        model.selectedOrganizationID = novel?.id
        #expect(model.visibleBooks.map(\.id) == [second.id])
    }

    @Test("Representative Chinese-first dataset searches within a bounded time")
    func representativePerformanceDataset() async throws {
        let repository = try makeRepository()
        try await repository.database.write { database in
            for bookIndex in 0..<60 {
                let book = Book(
                    title: "代表书籍 \(bookIndex)",
                    createdAt: referenceDate,
                    updatedAt: referenceDate
                )
                try book.insert(database)
                for chapterIndex in 0..<5 {
                    let paragraphs = (0..<10)
                        .map { "第\($0)段记录山川地理与人物故事，编号\(bookIndex)-\(chapterIndex)。" }
                        .joined(separator: "\n\n")
                    try Chapter(
                        bookID: book.id,
                        title: "第 \(chapterIndex) 章",
                        markdown: paragraphs,
                        position: chapterIndex,
                        createdAt: referenceDate,
                        updatedAt: referenceDate
                    )
                    .insert(database)
                }
            }
            _ = try LibrarySearchIndexer.rebuildAll(database)
        }

        let clock = ContinuousClock()
        let start = clock.now
        let results = try await repository.searchLibrary(
            "山川地理",
            scope: .content,
            trashScope: .activeLibrary
        )
        let elapsed = start.duration(to: clock.now)
        #expect(results.count == 250)
        #expect(elapsed < .seconds(3))
    }

    private func makeRepository() throws -> GRDBLibraryRepository {
        GRDBLibraryRepository(database: try LibraryDatabase.makeInMemory())
    }

    private func matches(
        _ query: String,
        in repository: GRDBLibraryRepository
    ) async throws -> [LibrarySearchResult] {
        try await repository.searchLibrary(
            query,
            scope: .content,
            trashScope: .activeLibrary
        )
    }

    private func libraryBook(
        title: String,
        authors: [String],
        tags: [String]
    ) -> LibraryBook {
        let id = UUID()
        return LibraryBook(
            id: id,
            title: title,
            subtitle: nil,
            authors: authors,
            summary: "",
            tags: tags,
            dateAdded: referenceDate,
            isFavorite: false,
            isCurrentlyReading: false,
            readingProgress: nil,
            isTrashed: false,
            coverStyle: .derived(from: id)
        )
    }
}
