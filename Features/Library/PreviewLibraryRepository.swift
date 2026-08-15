#if DEBUG
import Foundation

nonisolated final class PreviewLibraryRepository: LibraryRepository, Sendable {
    private let books: [LibraryBook]

    init(books: [LibraryBook]) {
        self.books = books
    }

    func observeLibraryBooks() -> AsyncThrowingStream<[LibraryBook], Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(books)
            continuation.finish()
        }
    }
}
#endif
