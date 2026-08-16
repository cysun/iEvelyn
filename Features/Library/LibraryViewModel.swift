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
    private(set) var isPreparingEPUB = false
    var alert: LibraryViewModelAlert?
    private var isObserving = false
    private var searchTask: Task<Void, Never>?
    private let coverCache = NSCache<NSUUID, NSData>()
    private let now: @Sendable () -> Date
    private let bookContentImporter: any BookContentImporting
    private let epubExporter: any EPUBExporting

    var destination: LibraryDestination = .allBooks {
        didSet {
            selectedOrganizationID = nil
            scheduleSearch()
        }
    }

    var presentation: LibraryPresentation = .grid

    var sortOrder: LibrarySortOrder = .title

    var searchText = "" {
        didSet { scheduleSearch() }
    }

    var searchScope: LibrarySearchScope = .all {
        didSet { scheduleSearch() }
    }

    var selectedOrganizationID: String?

    private(set) var searchResults: [LibrarySearchResult] = []
    private(set) var isSearching = false
    private(set) var searchErrorMessage: String?

    init(
        repository: any LibraryRepository,
        initialBooks: [LibraryBook] = [],
        referenceDate: Date = .now,
        now: @escaping @Sendable () -> Date = { .now },
        bookContentImporter: any BookContentImporting = BookContentImporter(),
        epubExporter: (any EPUBExporting)? = nil
    ) {
        self.repository = repository
        self.referenceDate = referenceDate
        self.now = now
        self.bookContentImporter = bookContentImporter
        self.epubExporter = epubExporter ?? EPUBExportService(repository: repository)
        books = initialBooks
        isLoading = initialBooks.isEmpty
        coverCache.countLimit = 80
        coverCache.totalCostLimit = 64 * 1_024 * 1_024
    }

    var visibleBooks: [LibraryBook] {
        let destinationBooks = LibraryQuery(
            destination: destination,
            searchText: "",
            sortOrder: sortOrder,
            referenceDate: referenceDate
        )
        .apply(to: books)
        guard let selectedOrganizationID else { return destinationBooks }
        return destinationBooks.filter { book in
            switch destination {
            case .authors:
                book.authors.contains {
                    LibraryNameNormalizer.normalize($0) == selectedOrganizationID
                }
            case .tags:
                book.tags.contains {
                    LibraryNameNormalizer.normalize($0) == selectedOrganizationID
                }
            default:
                true
            }
        }
    }

    var organizationGroups: [LibraryOrganizationGroup] {
        let activeBooks = books.filter { !$0.isTrashed }
        var groups: [String: (name: String, bookIDs: Set<UUID>)] = [:]
        for book in activeBooks {
            let values: [String]
            switch destination {
            case .authors:
                values = book.authors
            case .tags:
                values = book.tags
            default:
                return []
            }
            for value in values {
                let identifier = LibraryNameNormalizer.normalize(value)
                var group = groups[identifier] ?? (value, [])
                group.bookIDs.insert(book.id)
                groups[identifier] = group
            }
        }
        return groups.values
            .map { LibraryOrganizationGroup(name: $0.name, bookIDs: $0.bookIDs) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var visibleSearchResults: [LibrarySearchResult] {
        let visibleBookIDs = Set(visibleBooks.map(\.id))
        return searchResults.filter { visibleBookIDs.contains($0.bookID) }
    }

    var hasSearchQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    func selectOrganization(_ group: LibraryOrganizationGroup?) {
        selectedOrganizationID = group?.id
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

    func prepareEPUBExport(for book: LibraryBook) async -> EPUBExportPresentation? {
        guard !isPreparingEPUB else { return nil }
        isPreparingEPUB = true
        defer { isPreparingEPUB = false }

        do {
            let file = try await epubExporter.export(book: book)
            return EPUBExportPresentation(file: file)
        } catch is CancellationError {
            return nil
        } catch {
            alert = LibraryViewModelAlert(
                title: "Could Not Export EPUB",
                message: error.localizedDescription
            )
            return nil
        }
    }

    func reportEPUBFileWriteFailure(_ error: Error) {
        alert = LibraryViewModelAlert(
            title: "Could Not Save EPUB",
            message: error.localizedDescription
        )
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
                if hasSearchQuery {
                    scheduleSearch(delay: .zero)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleSearch(delay: Duration = .milliseconds(180)) {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            searchErrorMessage = nil
            isSearching = false
            return
        }

        let scope = searchScope
        let trashScope: LibrarySearchTrashScope = destination == .trash ? .trash : .activeLibrary
        isSearching = true
        searchErrorMessage = nil
        searchTask = Task { [weak self] in
            do {
                if delay != .zero {
                    try await Task.sleep(for: delay)
                }
                guard let self else { return }
                let results = try await repository.searchLibrary(
                    query,
                    scope: scope,
                    trashScope: trashScope
                )
                try Task.checkCancellation()
                guard self.searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query,
                      self.searchScope == scope else {
                    return
                }
                self.searchResults = results
                self.isSearching = false
                self.searchErrorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.searchResults = []
                self.isSearching = false
                self.searchErrorMessage = error.localizedDescription
            }
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
