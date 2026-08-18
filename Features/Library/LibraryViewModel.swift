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
    private(set) var isPreparingMarkdown = false
    private(set) var isSelectingBooks = false
    private(set) var selectedBookIDs: Set<UUID> = []
    var alert: LibraryViewModelAlert?
    private var isObserving = false
    private var searchTask: Task<Void, Never>?
    private let coverCache = NSCache<NSUUID, NSData>()
    private let now: @Sendable () -> Date
    private let bookContentImporter: any BookContentImporting
    private let epubExporter: any EPUBExporting
    private let markdownExporter: any MarkdownExporting

    var destination: LibraryDestination = .allBooks {
        didSet {
            endBookSelection()
            selectedOrganizationID = nil
            scheduleSearch()
        }
    }

    var presentation: LibraryPresentation = .grid

    var sortOrder: LibrarySortOrder = .recentlyOpened

    var searchText = "" {
        didSet {
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                endBookSelection()
            }
            scheduleSearch()
        }
    }

    var searchScope: LibrarySearchScope = .all {
        didSet { scheduleSearch() }
    }

    var selectedOrganizationID: String? {
        didSet {
            guard selectedOrganizationID != oldValue else { return }
            endBookSelection()
        }
    }

    private(set) var searchResults: [LibrarySearchResult] = []
    private(set) var isSearching = false
    private(set) var searchErrorMessage: String?

    init(
        repository: any LibraryRepository,
        initialBooks: [LibraryBook] = [],
        referenceDate: Date = .now,
        now: @escaping @Sendable () -> Date = { .now },
        bookContentImporter: any BookContentImporting = BookContentImporter(),
        epubExporter: (any EPUBExporting)? = nil,
        markdownExporter: (any MarkdownExporting)? = nil
    ) {
        self.repository = repository
        self.referenceDate = referenceDate
        self.now = now
        self.bookContentImporter = bookContentImporter
        self.epubExporter = epubExporter ?? EPUBExportService(repository: repository)
        self.markdownExporter = markdownExporter ?? MarkdownInterchangeService(repository: repository)
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

    var selectedBooks: [LibraryBook] {
        visibleBooks.filter { selectedBookIDs.contains($0.id) }
    }

    var selectedBooksWithProgress: [LibraryBook] {
        selectedBooks.filter(\.isCurrentlyReading)
    }

    var areAllVisibleBooksSelected: Bool {
        !visibleBooks.isEmpty && Set(visibleBooks.map(\.id)).isSubset(of: selectedBookIDs)
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

    func covers(for bookID: UUID) async throws -> [Asset] {
        try await repository.coverAssets(forBookID: bookID)
    }

    func addCovers(to bookID: UUID, from sourceURLs: [URL]) async throws {
        try await repository.addCovers(bookID: bookID, from: sourceURLs, at: now())
    }

    func makeCurrentCover(_ coverID: UUID, for bookID: UUID) async throws {
        try await repository.setCurrentCover(bookID: bookID, coverID: coverID, at: now())
    }

    func removeCover(_ coverID: UUID, from bookID: UUID) async throws {
        defer { coverCache.removeObject(forKey: coverID as NSUUID) }
        try await repository.removeCover(bookID: bookID, coverID: coverID, at: now())
    }

    func clearSearch() {
        searchText = ""
    }

    func beginBookSelection() {
        guard destination != .trash, !hasSearchQuery, !visibleBooks.isEmpty else { return }
        isSelectingBooks = true
        selectedBookIDs = []
    }

    func endBookSelection() {
        isSelectingBooks = false
        selectedBookIDs = []
    }

    func toggleBookSelection(_ book: LibraryBook) {
        guard isSelectingBooks,
              !book.isTrashed,
              visibleBooks.contains(where: { $0.id == book.id }) else {
            return
        }
        if selectedBookIDs.contains(book.id) {
            selectedBookIDs.remove(book.id)
        } else {
            selectedBookIDs.insert(book.id)
        }
    }

    func toggleSelectAllVisibleBooks() {
        guard isSelectingBooks else { return }
        let visibleBookIDs = Set(visibleBooks.map(\.id))
        if !visibleBookIDs.isEmpty, visibleBookIDs.isSubset(of: selectedBookIDs) {
            selectedBookIDs.subtract(visibleBookIDs)
        } else {
            selectedBookIDs.formUnion(visibleBookIDs)
        }
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
                at: now()
            )
            bookID = id
        } else {
            guard let contentFileURL = submission.contentFileURL else {
                throw BookContentImportError.contentFileRequired
            }
            let content = try await bookContentImporter.loadCompleteBook(from: contentFileURL)
            try content.validateMetadata(validatedMetadata)
            bookID = try await repository.createBook(
                metadata: submission.metadata,
                contentChapters: content.chapters,
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

    @discardableResult
    func moveSelectedBooksToTrash() async -> Bool {
        await moveBooksToTrash(bookIDs: selectedBooks.map(\.id))
    }

    @discardableResult
    func moveBooksToTrash(bookIDs: [UUID]) async -> Bool {
        guard !bookIDs.isEmpty else { return false }
        let succeeded = await performOperation(errorTitle: "Could Not Move Books to Trash") {
            try await repository.moveBooksToTrash(ids: bookIDs, at: now())
        }
        if succeeded {
            endBookSelection()
        }
        return succeeded
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

    @discardableResult
    func emptyTrash() async -> Bool {
        await performOperation(errorTitle: "Could Not Empty Trash") {
            _ = try await repository.emptyTrash()
        }
    }

    func clearReadingProgress(for book: LibraryBook) async {
        await performOperation(errorTitle: "Could Not Clear Reading Progress") {
            try await repository.clearReadingProgress(bookIDs: [book.id])
        }
    }

    @discardableResult
    func clearSelectedReadingProgress() async -> Bool {
        await clearReadingProgress(bookIDs: selectedBooksWithProgress.map(\.id))
    }

    @discardableResult
    func clearReadingProgress(bookIDs: [UUID]) async -> Bool {
        guard !bookIDs.isEmpty else { return false }
        let succeeded = await performOperation(errorTitle: "Could Not Clear Reading Progress") {
            try await repository.clearReadingProgress(bookIDs: bookIDs)
        }
        if succeeded {
            endBookSelection()
        }
        return succeeded
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

    func prepareEPUBExports(for books: [LibraryBook]) async -> [EPUBExportPresentation]? {
        guard !isPreparingEPUB, !books.isEmpty else { return nil }
        isPreparingEPUB = true
        defer { isPreparingEPUB = false }

        var presentations: [EPUBExportPresentation] = []
        presentations.reserveCapacity(books.count)
        for book in books {
            do {
                try Task.checkCancellation()
                let file = try await epubExporter.export(book: book)
                presentations.append(EPUBExportPresentation(file: file))
            } catch is CancellationError {
                return nil
            } catch {
                alert = LibraryViewModelAlert(
                    title: "Could Not Export \(book.title) as EPUB",
                    message: "No files were exported. \(error.localizedDescription)"
                )
                return nil
            }
        }
        return presentations
    }

    func reportEPUBFileWriteFailure(_ error: Error) {
        alert = LibraryViewModelAlert(
            title: "Could Not Save EPUB",
            message: error.localizedDescription
        )
    }

    func prepareMarkdownExport(for book: LibraryBook) async -> MarkdownExportPresentation? {
        guard !isPreparingMarkdown else { return nil }
        isPreparingMarkdown = true
        defer { isPreparingMarkdown = false }

        do {
            let file = try await markdownExporter.exportMarkdown(book: book)
            return MarkdownExportPresentation(file: file)
        } catch is CancellationError {
            return nil
        } catch {
            alert = LibraryViewModelAlert(
                title: "Could Not Export Markdown",
                message: error.localizedDescription
            )
            return nil
        }
    }

    func prepareMarkdownExports(for books: [LibraryBook]) async -> [MarkdownExportPresentation]? {
        guard !isPreparingMarkdown, !books.isEmpty else { return nil }
        isPreparingMarkdown = true
        defer { isPreparingMarkdown = false }

        var presentations: [MarkdownExportPresentation] = []
        presentations.reserveCapacity(books.count)
        for book in books {
            do {
                try Task.checkCancellation()
                let file = try await markdownExporter.exportMarkdown(book: book)
                presentations.append(MarkdownExportPresentation(file: file))
            } catch is CancellationError {
                return nil
            } catch {
                alert = LibraryViewModelAlert(
                    title: "Could Not Export \(book.title) as Markdown",
                    message: "No files were exported. \(error.localizedDescription)"
                )
                return nil
            }
        }
        return presentations
    }

    func reportMarkdownFileWriteFailure(_ error: Error) {
        alert = LibraryViewModelAlert(
            title: "Could Not Save Markdown",
            message: error.localizedDescription
        )
    }

    func markOpened(bookID: UUID) async {
        do {
            try await repository.markBookOpened(id: bookID, at: now())
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
                selectedBookIDs.formIntersection(Set(visibleBooks.map(\.id)))
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
