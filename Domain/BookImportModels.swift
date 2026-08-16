import Foundation

nonisolated struct ImportedBookChapter: Equatable, Sendable {
    let title: String
    let markdown: String
}

nonisolated enum BookContentFileMode: String, CaseIterable, Identifiable, Sendable {
    case replace
    case append

    var id: Self { self }

    var title: String {
        switch self {
        case .replace:
            "Replace"
        case .append:
            "Append"
        }
    }
}

nonisolated enum BookChapterUpdate: Equatable, Sendable {
    case unchanged
    case replace([ImportedBookChapter])
    case append([ImportedBookChapter])
}

nonisolated enum BookCoverUpdate: Equatable, Sendable {
    case unchanged
    case replace(URL)
    case remove
}

nonisolated struct BookEditorSubmission: Equatable, Sendable {
    let metadata: BookMetadataInput
    let contentFileURL: URL?
    let contentMode: BookContentFileMode
    let coverUpdate: BookCoverUpdate
}
