import Foundation
import WebKit

nonisolated enum ReaderBundledResourceError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case resourceUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The reader requested an unknown bundled resource."
        case .resourceUnavailable:
            "The Antique Paper texture is unavailable."
        }
    }
}

nonisolated enum ReaderBundledResource {
    static let scheme = "ievelyn-resource"
    static let antiquePaperURLString = "\(scheme)://reader/antique-paper.jpg"

    static func payload(for url: URL, bundle: Bundle = .main) throws -> LibraryAssetPayload {
        guard url.absoluteString == antiquePaperURLString else {
            throw ReaderBundledResourceError.invalidURL
        }
        guard let resourceURL = bundle.url(
            forResource: "ReaderAntiquePaper",
            withExtension: "jpg"
        ) else {
            throw ReaderBundledResourceError.resourceUnavailable
        }
        do {
            return LibraryAssetPayload(
                data: try Data(contentsOf: resourceURL, options: .mappedIfSafe),
                mediaType: "image/jpeg"
            )
        } catch {
            throw ReaderBundledResourceError.resourceUnavailable
        }
    }
}

nonisolated struct ReaderBundledResourceURLSchemeHandler: URLSchemeHandler {
    func reply(
        for request: URLRequest
    ) -> AsyncThrowingStream<URLSchemeTaskResult, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = request.url else {
                        throw ReaderBundledResourceError.invalidURL
                    }
                    let payload = try ReaderBundledResource.payload(for: url)
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
