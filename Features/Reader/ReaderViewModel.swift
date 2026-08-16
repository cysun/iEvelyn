import Foundation
import Observation

nonisolated struct ReaderRenderedChapter: Equatable, Sendable {
    let chapterID: Chapter.ID
    let document: String
    let cacheKey: MarkdownRenderCacheKey
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
    private var navigator = ReaderChapterNavigator()
    private var isObserving = false
    private var renderToken = 0

    private(set) var book: LibraryBook?
    private(set) var renderedChapter: ReaderRenderedChapter?
    private(set) var isLoadingBook = true
    private(set) var isLoadingChapters = true
    private(set) var isRendering = false
    private(set) var errorMessage: String?
    private(set) var renderErrorMessage: String?

    init(
        bookID: UUID,
        repository: any LibraryRepository,
        renderer: any MarkdownRendering = MarkdownRenderingService()
    ) {
        self.bookID = bookID
        self.repository = repository
        self.renderer = renderer
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

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.observeBook() }
            group.addTask { await self.observeChapters() }
            await group.waitForAll()
        }
    }

    func selectChapter(_ chapterID: Chapter.ID) {
        guard navigator.select(chapterID) else { return }
        prepareForChapterChange()
    }

    func movePrevious() {
        guard navigator.movePrevious() else { return }
        prepareForChapterChange()
    }

    func moveNext() {
        guard navigator.moveNext() else { return }
        prepareForChapterChange()
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
                navigator.updateChapters(observedChapters)
                isLoadingChapters = false
                if navigator.selectedChapterID != priorSelection {
                    prepareForChapterChange()
                }
            }
        } catch is CancellationError {
            return
        } catch {
            isLoadingChapters = false
            errorMessage = error.localizedDescription
        }
    }

    private func prepareForChapterChange() {
        renderToken &+= 1
        renderedChapter = nil
        renderErrorMessage = nil
        isRendering = selectedChapter != nil
    }
}
