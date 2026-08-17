import Observation
import SwiftUI
import WebKit

struct ReaderWebView: View {
    let document: String
    let loadID: ReaderRenderRequestID
    let restorationLocation: ReaderResolvedLocation
    let bookmarkNavigation: ReaderResolvedNavigation?
    let shouldFocus: Bool
    let focusRequestID: Int
    let onLocationChange: (ReaderLocationCapture) -> Void
    let onBookmarkNavigationCompleted: (UUID) -> Void

    @Environment(\.openURL) private var openURL
    @State private var page: WebPage
    @State private var linkRouter: ReaderExternalLinkRouter
    @State private var loadErrorMessage: String?
    @State private var trackingErrorMessage: String?
    @State private var retryGeneration = 0
    @State private var trackingRetryGeneration = 0
    @State private var loadedRequestID: ReaderRenderRequestID?
    @State private var loadedRetryGeneration: Int?
    @State private var lastReportedLocation: ReaderLocationCapture?

    init(
        document: String,
        loadID: ReaderRenderRequestID,
        assetLoader: BookAssetDataLoader,
        restorationLocation: ReaderResolvedLocation,
        bookmarkNavigation: ReaderResolvedNavigation?,
        shouldFocus: Bool,
        focusRequestID: Int,
        onLocationChange: @escaping (ReaderLocationCapture) -> Void,
        onBookmarkNavigationCompleted: @escaping (UUID) -> Void
    ) {
        self.document = document
        self.loadID = loadID
        self.restorationLocation = restorationLocation
        self.bookmarkNavigation = bookmarkNavigation
        self.shouldFocus = shouldFocus
        self.focusRequestID = focusRequestID
        self.onLocationChange = onLocationChange
        self.onBookmarkNavigationCompleted = onBookmarkNavigationCompleted

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
                ZStack(alignment: .bottom) {
                    WebView(page)
                        .webViewBackForwardNavigationGestures(.disabled)
                        .webViewMagnificationGestures(.disabled)
                        .webViewLinkPreviews(.disabled)
                        .webViewElementFullscreenBehavior(.disabled)
                        .background {
                            ReaderFocusRequester(
                                area: .readerPanel,
                                isActive: shouldFocus,
                                requestID: focusRequestID
                            )
                        }
                        .accessibilityLabel("Chapter content")
                        .accessibilityIdentifier("reader-chapter-content")

                    if let trackingErrorMessage {
                        HStack(spacing: 8) {
                            Label(trackingErrorMessage, systemImage: "bookmark.slash")
                                .lineLimit(2)
                            Button("Try Again") {
                                trackingRetryGeneration &+= 1
                            }
                        }
                        .font(.callout)
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding()
                        .accessibilityIdentifier("reader-location-error")
                    }
                }
            }
        }
        .task(id: operationID) {
            await loadRestoreAndMonitorLocation()
        }
        .onChange(of: linkRouter.pendingURL) { _, url in
            guard let url else { return }
            openURL(url)
            linkRouter.clear(url)
        }
    }

    private var operationID: ReaderWebOperationID {
        ReaderWebOperationID(
            request: loadID,
            loadRetryGeneration: retryGeneration,
            trackingRetryGeneration: trackingRetryGeneration,
            navigationID: bookmarkNavigation?.id
        )
    }

    private func loadRestoreAndMonitorLocation() async {
        let mustLoad = loadedRequestID != loadID || loadedRetryGeneration != retryGeneration
        do {
            if mustLoad {
                loadErrorMessage = nil
                trackingErrorMessage = nil
                for try await _ in page.load(html: document) {}
                try Task.checkCancellation()
                loadedRequestID = loadID
                loadedRetryGeneration = retryGeneration
                lastReportedLocation = nil
            }

            if let bookmarkNavigation {
                try await ReaderWebLocationBridge.restore(
                    bookmarkNavigation.location,
                    in: page
                )
                onBookmarkNavigationCompleted(bookmarkNavigation.id)
            } else if mustLoad {
                try await ReaderWebLocationBridge.restore(restorationLocation, in: page)
            }

            trackingErrorMessage = nil
            await captureAndReportLocation()
            while !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(700))
                await captureAndReportLocation()
            }
        } catch is CancellationError {
            return
        } catch {
            if mustLoad, loadedRequestID != loadID {
                loadErrorMessage = error.localizedDescription
            } else {
                trackingErrorMessage = "Reading position could not be saved."
            }
        }
    }

    private func captureAndReportLocation() async {
        do {
            let location = try await ReaderWebLocationBridge.capture(from: page)
            trackingErrorMessage = nil
            guard shouldReport(location) else { return }
            lastReportedLocation = location
            onLocationChange(location)
        } catch is CancellationError {
            return
        } catch {
            trackingErrorMessage = "Reading position could not be saved."
        }
    }

    private func shouldReport(_ location: ReaderLocationCapture) -> Bool {
        guard let lastReportedLocation else { return true }
        return location.stableBlockID != lastReportedLocation.stableBlockID
            || abs(location.fractionInChapter - lastReportedLocation.fractionInChapter) >= 0.003
    }
}

nonisolated private struct ReaderWebOperationID: Hashable {
    let request: ReaderRenderRequestID
    let loadRetryGeneration: Int
    let trackingRetryGeneration: Int
    let navigationID: UUID?
}

@MainActor
enum ReaderWebLocationBridge {
    private static let captureScript = """
        const root = document.scrollingElement || document.documentElement;
        const pointX = Math.max(1, Math.min(window.innerWidth / 2, root.clientWidth / 2));
        const pointY = Math.max(1, Math.min(window.innerHeight * 0.22, 180));
        const element = document.elementFromPoint(pointX, pointY);
        let block = element ? element.closest('.chapter [id]') : null;
        if (!block) {
          block = Array.from(document.querySelectorAll('.chapter [id]')).find((candidate) => {
            const bounds = candidate.getBoundingClientRect();
            return bounds.bottom > 0 && bounds.top < window.innerHeight;
          }) || null;
        }
        const maximum = Math.max(0, root.scrollHeight - root.clientHeight);
        const fraction = maximum > 0 ? root.scrollTop / maximum : 0;
        return [block ? block.id : '', Math.max(0, Math.min(1, fraction))];
        """

    private static let restoreScript = """
        const root = document.scrollingElement || document.documentElement;
        const requestedBlockID = blockID;
        const requestedFraction = Math.max(0, Math.min(1, fraction));
        const target = requestedBlockID ? document.getElementById(requestedBlockID) : null;
        if (target) {
          target.scrollIntoView({ block: 'start', inline: 'nearest' });
        } else {
          const maximum = Math.max(0, root.scrollHeight - root.clientHeight);
          root.scrollTop = maximum * requestedFraction;
        }
        return target !== null;
        """

    static func capture(from page: WebPage) async throws -> ReaderLocationCapture {
        let result = try await page.callJavaScript(
            captureScript,
            contentWorld: .defaultClient
        )
        guard let values = result as? [Any], values.count == 2,
              let fraction = values[1] as? NSNumber else {
            throw ReaderWebLocationError.invalidCapture
        }
        let stableBlockID = (values[0] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return ReaderLocationCapture(
            stableBlockID: stableBlockID,
            fractionInChapter: fraction.doubleValue
        )
    }

    @discardableResult
    static func restore(_ location: ReaderResolvedLocation, in page: WebPage) async throws -> Bool {
        let result = try await page.callJavaScript(
            restoreScript,
            arguments: [
                "blockID": location.stableBlockID ?? "",
                "fraction": location.fractionInChapter,
            ],
            contentWorld: .defaultClient
        )
        guard let didFindBlock = result as? Bool else {
            throw ReaderWebLocationError.invalidRestore
        }
        return didFindBlock
    }
}

nonisolated private enum ReaderWebLocationError: LocalizedError {
    case invalidCapture
    case invalidRestore

    var errorDescription: String? {
        switch self {
        case .invalidCapture:
            "The reader returned an invalid reading location."
        case .invalidRestore:
            "The reader could not confirm the restored location."
        }
    }
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
