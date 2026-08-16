import Foundation
import Observation

nonisolated struct BookAssetDataLoader: Sendable {
    private let repository: any LibraryRepository

    init(repository: any LibraryRepository) {
        self.repository = repository
    }

    func payload(for url: URL) async throws -> LibraryAssetPayload {
        try await repository.bookAssetPayload(for: url)
    }
}

@MainActor
@Observable
final class ChapterPreviewViewModel {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private struct PreviewRequest: Sendable {
        let markdown: String
        let chapter: Chapter
    }

    let assetLoader: BookAssetDataLoader

    private let repository: any LibraryRepository
    private let renderer: any MarkdownRendering
    private let debounceDuration: Duration
    private let sleep: Sleep
    private var latestRequest: PreviewRequest?
    private var renderToken = 0

    private(set) var result: MarkdownRenderResult?
    private(set) var isRendering = false
    private(set) var errorMessage: String?

    init(
        repository: any LibraryRepository,
        renderer: any MarkdownRendering,
        debounceDuration: Duration = .milliseconds(180),
        sleep: @escaping Sleep = { duration in
            try await ContinuousClock().sleep(for: duration)
        }
    ) {
        self.repository = repository
        self.renderer = renderer
        self.debounceDuration = debounceDuration
        self.sleep = sleep
        assetLoader = BookAssetDataLoader(repository: repository)
    }

    func render(markdown: String, chapter: Chapter, immediately: Bool = false) async {
        let request = PreviewRequest(markdown: markdown, chapter: chapter)
        latestRequest = request
        renderToken &+= 1
        let token = renderToken

        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            result = nil
            errorMessage = nil
            isRendering = false
            return
        }

        isRendering = true
        errorMessage = nil

        do {
            if !immediately {
                try await sleep(debounceDuration)
            }
            try Task.checkCancellation()
            let assets = try await repository.assets(forBookID: chapter.bookID)
            let rendered = try await renderer.render(
                MarkdownRenderRequest(
                    markdown: markdown,
                    bookID: chapter.bookID,
                    assets: assets,
                    mode: .readerHTML,
                    documentTitle: chapter.title
                )
            )
            try Task.checkCancellation()
            guard renderToken == token else { return }
            result = rendered
            isRendering = false
        } catch is CancellationError {
            if renderToken == token {
                isRendering = false
            }
        } catch {
            guard renderToken == token else { return }
            errorMessage = error.localizedDescription
            isRendering = false
        }
    }

    func retry() async {
        guard let latestRequest else { return }
        await render(
            markdown: latestRequest.markdown,
            chapter: latestRequest.chapter,
            immediately: true
        )
    }
}
