import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    private let repository: any LibraryRepository
    let referenceDate: Date
    private(set) var books: [LibraryBook]
    private(set) var isLoading: Bool
    private(set) var errorMessage: String?
    private(set) var isPerformingOperation = false
    var alert: LibraryViewModelAlert?
    private var isObserving = false
    private let coverCache = NSCache<NSUUID, NSData>()
    private let now: @Sendable () -> Date
    private let bookContentImporter: any BookContentImporting

    var destination: LibraryDestination = .allBooks

    var presentation: LibraryPresentation = .grid

    var sortOrder: LibrarySortOrder = .title

    var searchText = ""

    init(
        repository: any LibraryRepository,
        initialBooks: [LibraryBook] = [],
        referenceDate: Date = .now,
        now: @escaping @Sendable () -> Date = { .now },
        bookContentImporter: any BookContentImporting = BookContentImporter()
    ) {
        self.repository = repository
        self.referenceDate = referenceDate
        self.now = now
        self.bookContentImporter = bookContentImporter
        books = initialBooks
        isLoading = initialBooks.isEmpty
        coverCache.countLimit = 80
        coverCache.totalCostLimit = 64 * 1_024 * 1_024
    }

    var visibleBooks: [LibraryBook] {
        LibraryQuery(
            destination: destination,
            searchText: searchText,
            sortOrder: sortOrder,
            referenceDate: referenceDate
        )
        .apply(to: books)
    }

    func book(id: LibraryBook.ID) -> LibraryBook? {
        books.first { $0.id == id }
    }

    func loadCoverImage(for asset: Asset) async throws -> Data {
        let cacheKey = asset.id as NSUUID
        if let cachedData = coverCache.object(forKey: cacheKey) {
            return cachedData as Data
        }

        let data = try await repository.coverThumbnailData(for: asset)
        try Task.checkCancellation()
        coverCache.setObject(data as NSData, forKey: cacheKey, cost: data.count)
        return data
    }

    func reportCoverLoadFailure(_ error: Error) {
        guard alert == nil else { return }
        alert = LibraryViewModelAlert(
            title: "Cover Could Not Be Loaded",
            message: error.localizedDescription
        )
    }

    func clearSearch() {
        searchText = ""
    }

    @discardableResult
    func saveBook(id: UUID?, submission: BookEditorSubmission) async throws -> UUID {
        let validatedMetadata = try submission.metadata.validated()
        let bookID: UUID
        if let id {
            let chapterUpdate: BookChapterUpdate
            if let contentFileURL = submission.contentFileURL {
                switch submission.contentMode {
                case .replace:
                    let content = try await bookContentImporter.loadCompleteBook(from: contentFileURL)
                    try content.validateMetadata(validatedMetadata)
                    chapterUpdate = .replace(content.chapters)
                case .append:
                    chapterUpdate = .append(
                        try await bookContentImporter.loadAppendedChapters(from: contentFileURL)
                    )
                }
            } else {
                chapterUpdate = .unchanged
            }
            try await repository.updateBook(
                id: id,
                metadata: submission.metadata,
                chapterUpdate: chapterUpdate,
                coverUpdate: submission.coverUpdate,
                at: now()
            )
            bookID = id
        } else {
            guard let contentFileURL = submission.contentFileURL else {
                throw BookContentImportError.contentFileRequired
            }
            let content = try await bookContentImporter.loadCompleteBook(from: contentFileURL)
            try content.validateMetadata(validatedMetadata)
            let coverSourceURL: URL?
            if case .replace(let sourceURL) = submission.coverUpdate {
                coverSourceURL = sourceURL
            } else {
                coverSourceURL = nil
            }
            bookID = try await repository.createBook(
                metadata: submission.metadata,
                contentChapters: content.chapters,
                coverSourceURL: coverSourceURL,
                at: now()
            )
        }

        destination = .allBooks
        return bookID
    }

    func toggleFavorite(for book: LibraryBook) async {
        await performOperation(errorTitle: "Could Not Update Favorite") {
            try await repository.setFavorite(
                bookID: book.id,
                isFavorite: !book.isFavorite,
                at: now()
            )
        }
    }

    func moveToTrash(_ book: LibraryBook) async {
        await performOperation(errorTitle: "Could Not Move Book to Trash") {
            try await repository.moveBookToTrash(id: book.id, at: now())
        }
    }

    func restore(_ book: LibraryBook) async {
        await performOperation(errorTitle: "Could Not Restore Book") {
            try await repository.restoreBook(id: book.id, at: now())
        }
    }

    func permanentlyDelete(_ book: LibraryBook) async {
        await performOperation(errorTitle: "Could Not Delete Book") {
            try await repository.deleteBookPermanently(id: book.id)
        }
    }

    func markOpened(_ book: LibraryBook) async {
        guard !book.isTrashed else { return }
        do {
            try await repository.markBookOpened(id: book.id, at: now())
        } catch is CancellationError {
            return
        } catch {
            alert = LibraryViewModelAlert(
                title: "Could Not Update Recently Opened",
                message: error.localizedDescription
            )
        }
    }

    func observeLibrary() async {
        guard !isObserving else { return }
        isObserving = true
        isLoading = books.isEmpty
        errorMessage = nil
        defer { isObserving = false }

        do {
            for try await observedBooks in repository.observeLibraryBooks() {
                books = observedBooks
                isLoading = false
                errorMessage = nil
            }
        } catch is CancellationError {
            return
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func performOperation(
        errorTitle: String,
        operation: () async throws -> Void
    ) async -> Bool {
        guard !isPerformingOperation else { return false }
        isPerformingOperation = true
        defer { isPerformingOperation = false }

        do {
            try await operation()
            return true
        } catch is CancellationError {
            return false
        } catch let error as LibraryAssetError {
            let title: String
            if case .cleanupIncomplete = error {
                title = "Asset Cleanup Needed"
            } else {
                title = errorTitle
            }
            alert = LibraryViewModelAlert(
                title: title,
                message: error.localizedDescription
            )
            return false
        } catch {
            alert = LibraryViewModelAlert(
                title: errorTitle,
                message: error.localizedDescription
            )
            return false
        }
    }
}

nonisolated struct LibraryViewModelAlert: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let message: String
}
