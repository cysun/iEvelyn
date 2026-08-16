import SwiftUI
import WebKit

struct MarkdownLivePreviewView: View {
    @State private var model: ChapterPreviewViewModel
    let chapter: Chapter
    let markdown: String
    let generation: Int

    init(
        model: ChapterPreviewViewModel,
        chapter: Chapter,
        markdown: String,
        generation: Int
    ) {
        _model = State(initialValue: model)
        self.chapter = chapter
        self.markdown = markdown
        self.generation = generation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isRendering {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("Rendering preview")
                }
            }

            previewContent

            if let result = model.result, !result.issues.isEmpty {
                Label(issueSummary(result.issues), systemImage: "exclamationmark.shield")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(result.issues.map(\.message).joined(separator: "\n"))
                    .accessibilityIdentifier("chapter-preview-warning")
            }
        }
        .padding(.leading, 6)
        .task(
            id: PreviewTaskID(
                chapterID: chapter.id,
                generation: generation,
                documentTitle: chapter.title
            )
        ) {
            await model.render(markdown: markdown, chapter: chapter)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView {
                Label("Nothing to Preview", systemImage: "doc.text")
            } description: {
                Text("Start writing Markdown to see the rendered chapter.")
            }
            .accessibilityIdentifier("chapter-preview-empty")
        } else if let errorMessage = model.errorMessage {
            ContentUnavailableView {
                Label("Preview Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") {
                    Task { await model.retry() }
                }
                .accessibilityIdentifier("chapter-preview-retry")
            }
            .accessibilityIdentifier("chapter-preview-error")
        } else if let result = model.result {
            RenderedMarkdownWebView(
                html: result.document,
                cacheKey: result.cacheKey,
                assetLoader: model.assetLoader
            )
        } else {
            ContentUnavailableView {
                ProgressView()
                Text("Rendering Preview")
            }
            .accessibilityIdentifier("chapter-preview-loading")
        }
    }

    private func issueSummary(_ issues: [MarkdownRenderIssue]) -> String {
        issues.count == 1
            ? "1 preview warning"
            : "\(issues.count) preview warnings"
    }
}

private struct PreviewTaskID: Hashable {
    let chapterID: UUID
    let generation: Int
    let documentTitle: String
}

private struct RenderedMarkdownWebView: View {
    let html: String
    let cacheKey: MarkdownRenderCacheKey
    @State private var page: WebPage
    @State private var loadErrorMessage: String?

    init(
        html: String,
        cacheKey: MarkdownRenderCacheKey,
        assetLoader: BookAssetDataLoader
    ) {
        self.html = html
        self.cacheKey = cacheKey

        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.loadsSubresources = true
        configuration.allowsAirPlayForMediaPlayback = false
        var navigationPreferences = configuration.defaultNavigationPreferences
        navigationPreferences.allowsContentJavaScript = false
        configuration.defaultNavigationPreferences = navigationPreferences
        if let scheme = URLScheme(BookAssetReference.scheme) {
            configuration.urlSchemeHandlers[scheme] = BookAssetURLSchemeHandler(loader: assetLoader)
        }

        _page = State(
            initialValue: WebPage(
                configuration: configuration,
                navigationDecider: MarkdownPreviewNavigationDecider()
            )
        )
    }

    var body: some View {
        Group {
            if let loadErrorMessage {
                ContentUnavailableView {
                    Label("Preview Could Not Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadErrorMessage)
                }
            } else {
                WebView(page)
                    .webViewBackForwardNavigationGestures(.disabled)
                    .webViewMagnificationGestures(.disabled)
                    .webViewLinkPreviews(.disabled)
                    .webViewElementFullscreenBehavior(.disabled)
                    .accessibilityLabel("Rendered Markdown preview")
                    .accessibilityIdentifier("chapter-rendered-preview")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: cacheKey) {
            loadErrorMessage = nil
            do {
                for try await _ in page.load(html: html) {}
            } catch is CancellationError {
                return
            } catch {
                loadErrorMessage = error.localizedDescription
            }
        }
    }
}

nonisolated private struct BookAssetURLSchemeHandler: URLSchemeHandler {
    let loader: BookAssetDataLoader

    func reply(
        for request: URLRequest
    ) -> AsyncThrowingStream<URLSchemeTaskResult, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = request.url else {
                        throw LibraryAssetError.invalidAssetURL
                    }
                    let payload = try await loader.payload(for: url)
                    try Task.checkCancellation()
                    let response = URLResponse(
                        url: url,
                        mimeType: payload.mediaType,
                        expectedContentLength: payload.data.count,
                        textEncodingName: nil
                    )
                    continuation.yield(.response(response))
                    continuation.yield(.data(payload.data))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private struct MarkdownPreviewNavigationDecider: WebPage.NavigationDeciding {
    mutating func decidePolicy(
        for action: WebPage.NavigationAction,
        preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        preferences.allowsContentJavaScript = false
        guard let url = action.request.url else { return .cancel }
        if url.scheme == "about" {
            return .allow
        }
        return .cancel
    }
}
