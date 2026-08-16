import Foundation
import GRDB
import Testing
@testable import iEvelyn

@Suite("Markdown chapter editor", .serialized)
struct ChapterEditorTests {
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
                throw ChapterEditorTestError.missingFixture
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

    @MainActor
    @Test("Debounced autosave coalesces rapid edits and saves the latest text")
    func debouncedAutosave() async throws {
        let chapter = makeChapter(title: "First")
        let repository = EditorTestRepository(chapters: [chapter])
        let model = ChapterEditorViewModel(
            repository: repository,
            debounceDuration: .milliseconds(25)
        )
        #expect(await model.activate(chapter))

        model.updateMarkdown("First")
        model.updateMarkdown("First, newer")
        model.updateMarkdown("First, newest")

        try await waitUntil {
            await repository.requestCount() == 1 && model.saveState == .saved
        }
        #expect(await repository.savedMarkdown(for: chapter.id) == "First, newest")
        #expect(model.markdown == "First, newest")
    }

    @MainActor
    @Test("Switching chapters waits for the current draft to save")
    func switchingFlushesCurrentDraft() async throws {
        let first = makeChapter(title: "First")
        let second = makeChapter(title: "Second", position: 1)
        let repository = EditorTestRepository(chapters: [first, second])
        await repository.suspendNextSave()
        let model = ChapterEditorViewModel(
            repository: repository,
            debounceDuration: .seconds(30)
        )
        #expect(await model.activate(first))
        model.updateMarkdown("Unsaved first chapter")

        let switching = Task { await model.activate(second) }
        try await waitUntil { await repository.requestCount() == 1 }
        #expect(model.activeChapterID == first.id)

        await repository.resumeSuspendedSave()
        #expect(await switching.value)
        #expect(model.activeChapterID == second.id)
        #expect(await repository.savedMarkdown(for: first.id) == "Unsaved first chapter")
    }

    @MainActor
    @Test("A newer edit made during a save wins in a serialized follow-up save")
    func newerEditWinsDuringSave() async throws {
        let chapter = makeChapter(title: "Ordering")
        let repository = EditorTestRepository(chapters: [chapter])
        await repository.suspendNextSave()
        let model = ChapterEditorViewModel(
            repository: repository,
            debounceDuration: .seconds(30)
        )
        #expect(await model.activate(chapter))
        model.updateMarkdown("First draft")

        let flushing = Task { await model.flushPendingSave() }
        try await waitUntil { await repository.requestCount() == 1 }
        model.updateMarkdown("Newer draft")
        await repository.resumeSuspendedSave()

        #expect(await flushing.value)
        #expect(await repository.requestCount() == 2)
        #expect(await repository.savedMarkdown(for: chapter.id) == "Newer draft")
        #expect(model.saveState == .saved)
    }

    @MainActor
    @Test("Save errors retain the draft and recover through Retry")
    func saveErrorRecovery() async throws {
        let chapter = makeChapter(title: "Retry")
        let repository = EditorTestRepository(chapters: [chapter])
        await repository.failNextSave()
        let model = ChapterEditorViewModel(
            repository: repository,
            debounceDuration: .seconds(30)
        )
        #expect(await model.activate(chapter))
        model.updateMarkdown("Keep this draft")

        #expect(await model.flushPendingSave() == false)
        guard case .failed = model.saveState else {
            Issue.record("Expected a visible failed save state")
            return
        }
        #expect(model.markdown == "Keep this draft")
        #expect(model.hasUnsavedChanges)

        await model.retrySave()
        #expect(model.saveState == .saved)
        #expect(await repository.savedMarkdown(for: chapter.id) == "Keep this draft")
    }

    @MainActor
    @Test("Conflicting windows require an explicit reload or overwrite decision")
    func editingConflictRecovery() async throws {
        let database = try LibraryDatabase.makeInMemory()
        let repository = GRDBLibraryRepository(database: database)
        let bookID = try await repository.createBook(
            metadata: BookMetadataInput(title: "Conflict", authors: ["Test Author"]),
            at: referenceDate
        )
        let chapterID = try await repository.createChapter(
            bookID: bookID,
            title: "Shared",
            at: referenceDate
        )
        let original = try #require(try await repository.chapters(forBookID: bookID).first)
        let firstWindow = ChapterEditorViewModel(repository: repository, debounceDuration: .seconds(30))
        let secondWindow = ChapterEditorViewModel(repository: repository, debounceDuration: .seconds(30))
        #expect(await firstWindow.activate(original))
        #expect(await secondWindow.activate(original))

        firstWindow.updateMarkdown("First window")
        #expect(await firstWindow.flushPendingSave())
        secondWindow.updateMarkdown("Second window")
        #expect(await secondWindow.flushPendingSave() == false)
        #expect(secondWindow.hasConflict)
        #expect(secondWindow.markdown == "Second window")

        await secondWindow.overwriteStoredVersion()
        #expect(secondWindow.saveState == .saved)
        let stored = try #require(try await repository.chapters(forBookID: bookID).first)
        #expect(stored.markdown == "Second window")
        #expect(stored.renderRevision == 2)
    }

    @MainActor
    @Test("Imported source is one undoable edit and refreshes counts")
    func importIsUndoable() async throws {
        let chapter = makeChapter(title: "Import", markdown: "Original")
        let repository = EditorTestRepository(chapters: [chapter])
        let importer = EditorTestImporter(markdown: "# Imported\n\nUnicode 章节")
        let model = ChapterEditorViewModel(
            repository: repository,
            importer: importer,
            debounceDuration: .seconds(30)
        )
        #expect(await model.activate(chapter))
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false

        await model.importChapterSource(
            from: URL(filePath: "/tmp/chapter.md"),
            undoManager: undoManager
        )
        #expect(model.markdown == "# Imported\n\nUnicode 章节")
        #expect(undoManager.canUndo)
        try await waitUntil { model.metrics.wordCount == 3 }

        undoManager.undo()
        #expect(model.markdown == "Original")
        #expect(undoManager.canRedo)
    }

    private func makeChapter(
        title: String,
        markdown: String = "",
        position: Int = 0
    ) -> Chapter {
        Chapter(
            bookID: UUID(),
            title: title,
            markdown: markdown,
            position: position,
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
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

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await clock.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for the expected editor state")
    }
}

private actor EditorTestRepository: LibraryRepository {
    private var chaptersByID: [UUID: Chapter]
    private var requests: [(chapterID: UUID, markdown: String, revision: Int)] = []
    private var shouldSuspendNextSave = false
    private var suspendedSave: CheckedContinuation<Void, Never>?
    private var failuresRemaining = 0

    init(chapters: [Chapter]) {
        chaptersByID = Dictionary(uniqueKeysWithValues: chapters.map { ($0.id, $0) })
    }

    nonisolated func observeLibraryBooks() -> AsyncThrowingStream<[LibraryBook], Error> {
        AsyncThrowingStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }

    func updateChapterMarkdown(
        id: UUID,
        markdown: String,
        expectedRenderRevision: Int,
        at date: Date
    ) async throws -> Chapter {
        requests.append((id, markdown, expectedRenderRevision))
        if shouldSuspendNextSave {
            shouldSuspendNextSave = false
            await withCheckedContinuation { continuation in
                suspendedSave = continuation
            }
        }
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw ChapterEditorTestError.transientSaveFailure
        }
        guard var chapter = chaptersByID[id] else {
            throw LibraryRepositoryError.chapterNotFound
        }
        if chapter.markdown != markdown, chapter.renderRevision != expectedRenderRevision {
            throw ChapterRevisionConflict(storedChapter: chapter)
        }
        if chapter.markdown != markdown {
            chapter.markdown = markdown
            chapter.renderRevision += 1
            chapter.sourceHash = nil
            chapter.updatedAt = date
            chaptersByID[id] = chapter
        }
        return chapter
    }

    func suspendNextSave() {
        shouldSuspendNextSave = true
    }

    func resumeSuspendedSave() {
        suspendedSave?.resume()
        suspendedSave = nil
    }

    func failNextSave() {
        failuresRemaining += 1
    }

    func requestCount() -> Int {
        requests.count
    }

    func savedMarkdown(for chapterID: UUID) -> String? {
        chaptersByID[chapterID]?.markdown
    }
}

private nonisolated struct EditorTestImporter: ChapterSourceImporting {
    let markdown: String

    func loadUTF8Text(from sourceURL: URL) async throws -> String {
        markdown
    }
}

private nonisolated enum ChapterEditorTestError: LocalizedError {
    case missingFixture
    case transientSaveFailure

    var errorDescription: String? {
        switch self {
        case .missingFixture:
            "The test fixture is missing."
        case .transientSaveFailure:
            "Temporary save failure."
        }
    }
}
