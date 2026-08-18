import Foundation
import WebKit

nonisolated struct BookAssetDataLoader: Sendable {
    private let repository: any LibraryRepository

    init(repository: any LibraryRepository) {
        self.repository = repository
    }

    func payload(for url: URL) async throws -> LibraryAssetPayload {
        try await repository.bookAssetPayload(for: url)
    }
}

nonisolated struct BookAssetURLSchemeHandler: URLSchemeHandler {
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

@MainActor
enum BookContentWebConfiguration {
    static func make(assetLoader: BookAssetDataLoader) -> WebPage.Configuration {
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
        if let scheme = URLScheme(ReaderBundledResource.scheme) {
            configuration.urlSchemeHandlers[scheme] = ReaderBundledResourceURLSchemeHandler()
        }
        return configuration
    }
}
