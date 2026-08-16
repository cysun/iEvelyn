import Foundation
import Observation

nonisolated struct ReaderRenderedChapter: Equatable, Sendable {
    let chapterID: Chapter.ID
    let document: String
    let cacheKey: MarkdownRenderCacheKey
    let blocks: [MarkdownRenderedBlock]
    let issues: [MarkdownRenderIssue]
}

nonisolated struct ReaderRenderRequestID: Hashable, Sendable {
    let chapterID: Chapter.ID?
    let renderRevision: Int?
    let preferences: ReaderPreferences
}

@MainActor
@Observable
final class ReaderViewModel {
    let bookID: UUID
    let assetLoader: BookAssetDataLoader

    private let repository: any LibraryRepository
    private let renderer: any MarkdownRendering
    private let now: @Sendable () -> Date
    private let initialSearchTarget: ReaderSearchTarget?
    private var navigator = ReaderChapterNavigator()
    private var isObserving = false
    private var hasAppliedInitialProgress = false
    private var hasAppliedInitialSearchTarget = false
    private var renderToken = 0
    private var restoredProgress: ReadingProgress?
    private var currentLocation: (chapterID: Chapter.ID, anchor: ReaderLocationAnchor)?
    private var pendingProgress: ReadingProgress?
    private var progressSaveTask: Task<Void, Never>?

    private(set) var book: LibraryBook?
    private(set) var bookmarks: [Bookmark] = []
    private(set) var renderedChapter: ReaderRenderedChapter?
    private(set) var bookmarkNavigation: ReaderBookmarkNavigation?
    private(set) var isLoadingBook = true
    private(set) var isLoadingChapters = true
    private(set) var isRendering = false
    private(set) var errorMessage: String?
    private(set) var renderErrorMessage: String?
    private(set) var persistenceErrorMessage: String?

    init(
        bookID: UUID,
        searchTarget: ReaderSearchTarget? = nil,
        repository: any LibraryRepository,
        renderer: any MarkdownRendering = MarkdownRenderingService(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.bookID = bookID
        initialSearchTarget = searchTarget
        self.repository = repository
        self.renderer = renderer
        self.now = now
        assetLoader = BookAssetDataLoader(repository: repository)
    }

    var chapters: [Chapter] {
        navigator.chapters
    }

    var selectedChapter: Chapter? {
        navigator.selectedChapter
    }

    var selectedChapterID: Chapter.ID? {
        navigator.selectedChapterID
    }

    var canMovePrevious: Bool {
        navigator.canMovePrevious
    }

    var canMoveNext: Bool {
        navigator.canMoveNext
    }

    var chapterPositionDescription: String? {
        guard let selectedIndex = navigator.selectedIndex else { return nil }
        return "Chapter \(selectedIndex + 1) of \(chapters.count)"
    }

    func renderRequestID(for preferences: ReaderPreferences) -> ReaderRenderRequestID {
        ReaderRenderRequestID(
            chapterID: selectedChapter?.id,
            renderRevision: selectedChapter?.renderRevision,
            preferences: preferences
        )
    }

    func observe() async {
        guard !isObserving else { return }
        isObserving = true
        defer { isObserving = false }

        do {
            restoredProgress = try await repository.readingProgress(forBookID: bookID)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.observeBook() }
            group.addTask { await self.observeChapters() }
            group.addTask { await self.observeBookmarks() }
            await group.waitForAll()
        }
    }

    func selectChapter(_ chapterID: Chapter.ID) {
        persistPendingProgressInBackground()
        guard navigator.select(chapterID) else { return }
        bookmarkNavigation = nil
        prepareForChapterChange()
        stageProgress(at: ReaderLocationAnchor(), chapterID: chapterID)
    }

    func movePrevious() {
        persistPendingProgressInBackground()
        guard navigator.movePrevious() else { return }
        bookmarkNavigation = nil
        prepareForChapterChange()
        if let selectedChapterID {
            stageProgress(at: ReaderLocationAnchor(), chapterID: selectedChapterID)
        }
    }

    func moveNext() {
        persistPendingProgressInBackground()
        guard navigator.moveNext() else { return }
        bookmarkNavigation = nil
        prepareForChapterChange()
        if let selectedChapterID {
            stageProgress(at: ReaderLocationAnchor(), chapterID: selectedChapterID)
        }
    }

    func recordLocation(_ capture: ReaderLocationCapture, chapterID: Chapter.ID) {
        guard selectedChapterID == chapterID,
              let renderedChapter,
              renderedChapter.chapterID == chapterID,
              let chapterIndex = chapters.firstIndex(where: { $0.id == chapterID }) else {
            return
        }

        let anchor = ReaderSemanticAnchor.make(from: capture, blocks: renderedChapter.blocks)
        stageProgress(at: anchor, chapterID: chapterID, chapterIndex: chapterIndex)
    }

    func restorationLocation(for renderedChapter: ReaderRenderedChapter) -> ReaderResolvedLocation {
        if let currentLocation, currentLocation.chapterID == renderedChapter.chapterID {
            return ReaderSemanticAnchor.resolve(currentLocation.anchor, in: renderedChapter.blocks)
        }
        if let restoredProgress, restoredProgress.chapterID == renderedChapter.chapterID {
            return ReaderSemanticAnchor.resolve(
                ReaderLocationAnchor(progress: restoredProgress),
                in: renderedChapter.blocks
            )
        }
        let fallbackFraction = restoredProgress?.chapterID == nil
            ? restoredProgress?.fractionInChapter ?? 0
            : 0
        return ReaderSemanticAnchor.resolve(
            ReaderLocationAnchor(fractionInChapter: fallbackFraction),
            in: renderedChapter.blocks
        )
    }

    func resolvedBookmarkNavigation(
        for renderedChapter: ReaderRenderedChapter
    ) -> ReaderResolvedNavigation? {
        guard let bookmarkNavigation,
              bookmarkNavigation.chapterID == renderedChapter.chapterID else {
            return nil
        }
        return ReaderResolvedNavigation(
            id: bookmarkNavigation.id,
            location: ReaderSemanticAnchor.resolve(
                bookmarkNavigation.anchor,
                in: renderedChapter.blocks
            )
        )
    }

    func completeBookmarkNavigation(id: UUID) {
        guard bookmarkNavigation?.id == id else { return }
        bookmarkNavigation = nil
    }

    @discardableResult
    func addBookmark() async -> Bool {
        guard let chapter = selectedChapter else { return false }
        let anchor: ReaderLocationAnchor
        if let currentLocation, currentLocation.chapterID == chapter.id {
            anchor = currentLocation.anchor
        } else {
            anchor = ReaderLocationAnchor()
        }
        let date = now()
        let bookmark = Bookmark(
            bookID: bookID,
            chapterID: chapter.id,
            stableBlockID: anchor.stableBlockID,
            textQuote: anchor.textQuote,
            contextBefore: anchor.contextBefore,
            contextAfter: anchor.contextAfter,
            fractionInChapter: anchor.fractionInChapter,
            label: nil,
            note: nil,
            createdAt: date,
            updatedAt: date
        )
        return await performBookmarkOperation {
            try await repository.createBookmark(bookmark)
        }
    }

    @discardableResult
    func deleteBookmark(_ bookmark: Bookmark) async -> Bool {
        await performBookmarkOperation {
            try await repository.deleteBookmark(id: bookmark.id, bookID: bookID)
        }
    }

    func navigate(to bookmark: Bookmark) {
        let destinationChapterID: Chapter.ID
        let anchor: ReaderLocationAnchor
        if let chapterID = bookmark.chapterID,
           chapters.contains(where: { $0.id == chapterID }) {
            destinationChapterID = chapterID
            anchor = ReaderLocationAnchor(bookmark: bookmark)
        } else if let firstChapterID = chapters.first?.id {
            destinationChapterID = firstChapterID
            anchor = ReaderLocationAnchor(fractionInChapter: bookmark.fractionInChapter ?? 0)
        } else {
            return
        }

        persistPendingProgressInBackground()
        guard navigator.select(destinationChapterID) else { return }
        bookmarkNavigation = ReaderBookmarkNavigation(
            chapterID: destinationChapterID,
            anchor: anchor
        )
        stageProgress(at: anchor, chapterID: destinationChapterID)
        if renderedChapter?.chapterID != destinationChapterID {
            prepareForChapterChange()
        }
    }

    func chapterTitle(for bookmark: Bookmark) -> String {
        guard let chapterID = bookmark.chapterID,
              let chapter = chapters.first(where: { $0.id == chapterID }) else {
            return "Chapter unavailable"
        }
        return chapter.title
    }

    func bookmarkTitle(_ bookmark: Bookmark) -> String {
        if let quote = bookmark.textQuote, !quote.isEmpty {
            return String(quote.prefix(72))
        }
        return chapterTitle(for: bookmark)
    }

    func clearPersistenceError() {
        persistenceErrorMessage = nil
    }

    func flushReadingProgress() async {
        progressSaveTask?.cancel()
        progressSaveTask = nil
        await persistStagedProgress()
    }

    private func persistStagedProgress() async {
        guard let progress = pendingProgress else { return }
        pendingProgress = nil
        await persist(progress)
    }

    func renderSelectedChapter(preferences: ReaderPreferences) async {
        guard let chapter = selectedChapter else {
            renderedChapter = nil
            renderErrorMessage = nil
            isRendering = false
            return
        }

        renderToken &+= 1
        let token = renderToken
        isRendering = true
        renderErrorMessage = nil

        do {
            let assets = try await repository.assets(forBookID: bookID)
            let result = try await renderer.render(
                MarkdownRenderRequest(
                    markdown: chapter.markdown,
                    bookID: bookID,
                    assets: assets,
                    mode: .readerHTML,
                    documentTitle: chapter.title
                )
            )
            try Task.checkCancellation()
            let styledDocument = try ReaderDocumentStyler.apply(preferences, to: result.document)
            try Task.checkCancellation()
            guard renderToken == token, selectedChapterID == chapter.id else { return }
            renderedChapter = ReaderRenderedChapter(
                chapterID: chapter.id,
                document: styledDocument,
                cacheKey: result.cacheKey,
                blocks: result.blocks,
                issues: result.issues
            )
            isRendering = false
        } catch is CancellationError {
            if renderToken == token {
                isRendering = false
            }
        } catch {
            guard renderToken == token else { return }
            renderErrorMessage = error.localizedDescription
            isRendering = false
        }
    }

    private func observeBook() async {
        do {
            for try await books in repository.observeLibraryBooks() {
                book = books.first { $0.id == bookID && !$0.isTrashed }
                isLoadingBook = false
                if book == nil {
                    errorMessage = "This book is no longer available in the library."
                } else if errorMessage == "This book is no longer available in the library." {
                    errorMessage = nil
                }
            }
        } catch is CancellationError {
            return
        } catch {
            isLoadingBook = false
            errorMessage = error.localizedDescription
        }
    }

    private func observeChapters() async {
        do {
            for try await observedChapters in repository.observeChapters(forBookID: bookID) {
                let priorSelection = navigator.selectedChapterID
                let isApplyingInitialProgress = !hasAppliedInitialProgress
                let preferredChapterID = preferredInitialChapterID(in: observedChapters)
                navigator.updateChapters(
                    observedChapters,
                    preferredChapterID: preferredChapterID
                )
                applyInitialSearchTarget(in: observedChapters)
                bookmarks.sort(by: bookmarkComesBefore)
                hasAppliedInitialProgress = true
                isLoadingChapters = false
                if navigator.selectedChapterID != priorSelection {
                    if let pendingChapterID = pendingProgress?.chapterID,
                       !observedChapters.contains(where: { $0.id == pendingChapterID }) {
                        progressSaveTask?.cancel()
                        progressSaveTask = nil
                        pendingProgress = nil
                    }
                    if currentLocation?.chapterID != navigator.selectedChapterID {
                        currentLocation = nil
                    }
                    prepareForChapterChange()
                    if let selectedChapterID = navigator.selectedChapterID,
                       !isApplyingInitialProgress || restoredProgress == nil {
                        stageProgress(at: ReaderLocationAnchor(), chapterID: selectedChapterID)
                    }
                }
            }
        } catch is CancellationError {
            return
        } catch {
            isLoadingChapters = false
            errorMessage = error.localizedDescription
        }
    }

    private func observeBookmarks() async {
        do {
            for try await observedBookmarks in repository.observeBookmarks(forBookID: bookID) {
                bookmarks = observedBookmarks.sorted(by: bookmarkComesBefore)
            }
        } catch is CancellationError {
            return
        } catch {
            persistenceErrorMessage = error.localizedDescription
        }
    }

    private func preferredInitialChapterID(in observedChapters: [Chapter]) -> Chapter.ID? {
        guard !hasAppliedInitialProgress, !observedChapters.isEmpty else {
            return nil
        }
        if let targetChapterID = initialSearchTarget?.chapterID,
           observedChapters.contains(where: { $0.id == targetChapterID }) {
            return targetChapterID
        }
        guard
              let restoredProgress else {
            return nil
        }
        if let chapterID = restoredProgress.chapterID,
           observedChapters.contains(where: { $0.id == chapterID }) {
            return chapterID
        }
        guard let index = ReaderProgressCalculator.chapterIndex(
            for: restoredProgress.overallProgress,
            chapterCount: observedChapters.count
        ) else {
            return nil
        }
        return observedChapters.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.id.databaseString < $1.id.databaseString
        }[index].id
    }

    private func applyInitialSearchTarget(in observedChapters: [Chapter]) {
        guard !hasAppliedInitialSearchTarget,
              let target = initialSearchTarget,
              observedChapters.contains(where: { $0.id == target.chapterID }) else {
            return
        }
        hasAppliedInitialSearchTarget = true
        bookmarkNavigation = ReaderBookmarkNavigation(
            chapterID: target.chapterID,
            anchor: ReaderLocationAnchor(
                stableBlockID: target.stableBlockID,
                textQuote: target.textQuote,
                fractionInChapter: target.fractionInChapter
            )
        )
    }

    private func bookmarkComesBefore(_ lhs: Bookmark, _ rhs: Bookmark) -> Bool {
        let lhsIndex = lhs.chapterID.flatMap { id in chapters.firstIndex(where: { $0.id == id }) }
        let rhsIndex = rhs.chapterID.flatMap { id in chapters.firstIndex(where: { $0.id == id }) }
        switch (lhsIndex, rhsIndex) {
        case let (left?, right?) where left != right:
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            let leftFraction = lhs.fractionInChapter ?? 0
            let rightFraction = rhs.fractionInChapter ?? 0
            if leftFraction != rightFraction { return leftFraction < rightFraction }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.databaseString < rhs.id.databaseString
        }
    }

    private func scheduleProgressSave() {
        progressSaveTask?.cancel()
        progressSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(650))
            } catch {
                return
            }
            await self?.persistStagedProgress()
        }
    }

    private func stageProgress(
        at anchor: ReaderLocationAnchor,
        chapterID: Chapter.ID,
        chapterIndex suppliedChapterIndex: Int? = nil
    ) {
        guard let chapterIndex = suppliedChapterIndex
            ?? chapters.firstIndex(where: { $0.id == chapterID }) else {
            return
        }
        currentLocation = (chapterID, anchor)
        pendingProgress = ReadingProgress(
            bookID: bookID,
            chapterID: chapterID,
            stableBlockID: anchor.stableBlockID,
            textQuote: anchor.textQuote,
            contextBefore: anchor.contextBefore,
            contextAfter: anchor.contextAfter,
            fractionInChapter: anchor.fractionInChapter,
            overallProgress: ReaderProgressCalculator.overallProgress(
                chapterIndex: chapterIndex,
                chapterCount: chapters.count,
                fractionInChapter: anchor.fractionInChapter
            ),
            lastReadAt: now()
        )
        scheduleProgressSave()
    }

    private func persistPendingProgressInBackground() {
        progressSaveTask?.cancel()
        progressSaveTask = nil
        guard let progress = pendingProgress else { return }
        pendingProgress = nil
        Task {
            await persist(progress)
        }
    }

    private func persist(_ progress: ReadingProgress) async {
        do {
            try await repository.saveReadingProgress(progress)
            if restoredProgress.map({ $0.lastReadAt <= progress.lastReadAt }) ?? true {
                restoredProgress = progress
            }
            persistenceErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            pendingProgress = progress
            persistenceErrorMessage = error.localizedDescription
        }
    }

    private func performBookmarkOperation(
        _ operation: () async throws -> Void
    ) async -> Bool {
        do {
            try await operation()
            persistenceErrorMessage = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            persistenceErrorMessage = error.localizedDescription
            return false
        }
    }

    private func prepareForChapterChange() {
        renderToken &+= 1
        renderedChapter = nil
        renderErrorMessage = nil
        isRendering = selectedChapter != nil
    }
}
