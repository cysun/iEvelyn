import Observation
import SwiftUI
import WebKit

struct ReaderWebView: View {
    let document: String
    let loadID: ReaderRenderRequestID

    @Environment(\.openURL) private var openURL
    @State private var page: WebPage
    @State private var linkRouter: ReaderExternalLinkRouter
    @State private var loadErrorMessage: String?
    @State private var retryGeneration = 0

    init(
        document: String,
        loadID: ReaderRenderRequestID,
        assetLoader: BookAssetDataLoader
    ) {
        self.document = document
        self.loadID = loadID

        let router = ReaderExternalLinkRouter()
        _linkRouter = State(initialValue: router)
        _page = State(
            initialValue: WebPage(
                configuration: BookContentWebConfiguration.make(assetLoader: assetLoader),
                navigationDecider: ReaderNavigationDecider(linkRouter: router)
            )
        )
    }

    var body: some View {
        Group {
            if let loadErrorMessage {
                ContentUnavailableView {
                    Label("Chapter Could Not Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadErrorMessage)
                } actions: {
                    Button("Try Again") {
                        retryGeneration &+= 1
                    }
                    .accessibilityIdentifier("reader-web-retry")
                }
                .accessibilityIdentifier("reader-web-error")
            } else {
                WebView(page)
                    .webViewBackForwardNavigationGestures(.disabled)
                    .webViewMagnificationGestures(.disabled)
                    .webViewLinkPreviews(.disabled)
                    .webViewElementFullscreenBehavior(.disabled)
                    .accessibilityLabel("Chapter content")
                    .accessibilityIdentifier("reader-chapter-content")
            }
        }
        .task(id: ReaderWebLoadID(request: loadID, retryGeneration: retryGeneration)) {
            loadErrorMessage = nil
            do {
                for try await _ in page.load(html: document) {}
            } catch is CancellationError {
                return
            } catch {
                loadErrorMessage = error.localizedDescription
            }
        }
        .onChange(of: linkRouter.pendingURL) { _, url in
            guard let url else { return }
            openURL(url)
            linkRouter.clear(url)
        }
    }
}

nonisolated private struct ReaderWebLoadID: Hashable {
    let request: ReaderRenderRequestID
    let retryGeneration: Int
}

@MainActor
@Observable
private final class ReaderExternalLinkRouter {
    private(set) var pendingURL: URL?

    func requestOpen(_ url: URL) {
        pendingURL = url
    }

    func clear(_ url: URL) {
        guard pendingURL == url else { return }
        pendingURL = nil
    }
}

@MainActor
private struct ReaderNavigationDecider: WebPage.NavigationDeciding {
    let linkRouter: ReaderExternalLinkRouter

    mutating func decidePolicy(
        for action: WebPage.NavigationAction,
        preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        preferences.allowsContentJavaScript = false
        guard let url = action.request.url else { return .cancel }

        switch ReaderURLPolicy.decision(
            for: url,
            isUserActivatedLink: action.navigationType == .linkActivated
        ) {
        case .allowTrustedDocument:
            return .allow
        case .openExternally:
            linkRouter.requestOpen(url)
            return .cancel
        case .block:
            return .cancel
        }
    }
}
