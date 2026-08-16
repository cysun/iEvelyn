import Foundation

nonisolated protocol ChapterSourceImporting: Sendable {
    func loadUTF8Text(from sourceURL: URL) async throws -> String
}

nonisolated enum ChapterSourceImportError: LocalizedError, Equatable {
    case unsupportedFileType
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            "Choose a Markdown (.md or .markdown) or plain-text (.txt) file."
        case .invalidUTF8:
            "The selected file is not valid UTF-8 text."
        }
    }
}

nonisolated struct ChapterSourceImporter: ChapterSourceImporting {
    private static let supportedExtensions = Set(["md", "markdown", "txt"])

    func loadUTF8Text(from sourceURL: URL) async throws -> String {
        guard Self.supportedExtensions.contains(sourceURL.pathExtension.lowercased()) else {
            throw ChapterSourceImportError.unsupportedFileType
        }

        let didAccessSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        guard var text = String(data: data, encoding: .utf8) else {
            throw ChapterSourceImportError.invalidUTF8
        }
        if text.first == "\u{feff}" {
            text.removeFirst()
        }
        return text
    }
}
