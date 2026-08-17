import SwiftUI

struct ReaderApplicationRootView: View {
    @Bindable var applicationModel: LibraryApplicationModel
    let route: ReaderWindowRoute?
    let settings: ReaderSettingsStore

    var body: some View {
        Group {
            if let route, let repository = applicationModel.repository {
                ReaderView(
                    bookID: route.bookID,
                    searchTarget: route.searchTarget,
                    repository: repository,
                    settings: settings
                )
            } else if route == nil {
                ContentUnavailableView {
                    Label("Book Unavailable", systemImage: "book.closed")
                } description: {
                    Text("This reader window is not associated with a book.")
                }
                .accessibilityIdentifier("reader-invalid-route")
            } else if applicationModel.isLoading {
                ContentUnavailableView {
                    ProgressView()
                    Text("Opening Reader")
                } description: {
                    Text("Preparing the local library…")
                }
                .accessibilityIdentifier("reader-library-loading")
            } else {
                ContentUnavailableView {
                    Label("Reader Unavailable", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(applicationModel.loadErrorMessage ?? "The local library could not be opened.")
                } actions: {
                    Button("Try Again") {
                        Task { await applicationModel.retryLoading() }
                    }
                }
                .accessibilityIdentifier("reader-library-error")
            }
        }
        .task {
            await applicationModel.loadLibraryIfNeeded()
        }
    }
}

struct ReaderView: View {
    @State private var model: ReaderViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var sidebarMode: ReaderSidebarMode = .contents
    @State private var isFindPresented = false
    @State private var findQuery = ""
    @State private var isAppearancePresented = false
    @State private var bookmarkPendingDeletion: Bookmark?
    @State private var focusedArea = ReaderFocusArea.readerPanel
    @State private var focusRequestID = 0

    let settings: ReaderSettingsStore

    init(
        bookID: UUID,
        searchTarget: ReaderSearchTarget? = nil,
        repository: any LibraryRepository,
        settings: ReaderSettingsStore
    ) {
        _model = State(
            initialValue: ReaderViewModel(
                bookID: bookID,
                searchTarget: searchTarget,
                repository: repository
            )
        )
        self.settings = settings
    }

    var body: some View {
        @Bindable var settings = settings
        let preferences = settings.preferences
        let renderRequestID = model.renderRequestID(for: preferences)

        NavigationSplitView(columnVisibility: $columnVisibility) {
            readerSidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 240, max: 340)
        } detail: {
            readerContent(preferences: preferences, renderRequestID: renderRequestID)
        }
        .navigationTitle(model.book?.title ?? "Reader")
        .toolbar {
            readerToolbar(settings: settings)
        }
        .windowToolbarFullScreenVisibility(.onHover)
        .frame(minWidth: 720, idealWidth: 1_080, minHeight: 520, idealHeight: 760)
        .accessibilityIdentifier("reader-root")
        .background {
            ReaderKeyboardShortcutMonitor(onCommand: handleReaderKeyCommand)
        }
        .task {
            await model.observe()
        }
        .task(id: renderRequestID) {
            await model.renderSelectedChapter(preferences: preferences)
        }
        .onDisappear {
            Task { await model.flushReadingProgress() }
        }
        .onChange(of: columnVisibility) { _, visibility in
            let sidebarIsVisible = visibility != .detailOnly
            requestFocus(sidebarIsVisible ? .sidebar : .readerPanel)
        }
        .safeAreaInset(edge: .bottom) {
            if let persistenceErrorMessage = model.persistenceErrorMessage {
                HStack(spacing: 10) {
                    Label(persistenceErrorMessage, systemImage: "exclamationmark.triangle")
                        .lineLimit(2)
                    Spacer()
                    Button("Dismiss") {
                        model.clearPersistenceError()
                    }
                }
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.bar)
                .accessibilityIdentifier("reader-persistence-error")
            }
        }
        .confirmationDialog(
            "Delete Bookmark?",
            isPresented: deleteBookmarkIsPresented,
            titleVisibility: .visible,
            presenting: bookmarkPendingDeletion
        ) { bookmark in
            Button("Delete Bookmark", role: .destructive) {
                Task { _ = await model.deleteBookmark(bookmark) }
            }
            .accessibilityIdentifier("reader-bookmark-confirm-delete")
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the saved location from this book.")
        }
    }

    private var readerSidebar: some View {
        VStack(spacing: 0) {
            Picker("Reader Sidebar", selection: $sidebarMode) {
                ForEach(ReaderSidebarMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            .accessibilityIdentifier("reader-sidebar-mode")

            switch sidebarMode {
            case .contents:
                tableOfContents
            case .bookmarks:
                bookmarkList
            }
        }
    }

    private var tableOfContents: some View {
        List(selection: chapterSelection) {
            Section("Table of Contents") {
                ForEach(model.chapters) { chapter in
                    Text(chapter.title)
                        .lineLimit(2)
                        .tag(chapter.id)
                        .accessibilityIdentifier("reader-toc-chapter-\(chapter.id.databaseString)")
                }
            }
        }
        .background {
            ReaderFocusRequester(
                area: .sidebar,
                isActive: focusedArea == .sidebar,
                requestID: focusRequestID
            )
        }
        .accessibilityLabel("Table of Contents")
        .accessibilityIdentifier("reader-table-of-contents")
    }

    private var bookmarkList: some View {
        List {
            if model.bookmarks.isEmpty {
                ContentUnavailableView {
                    Label("No Bookmarks", systemImage: "bookmark")
                } description: {
                    Text("Add a bookmark from the reader toolbar to save this location.")
                }
                .accessibilityIdentifier("reader-bookmarks-empty")
            } else {
                ForEach(model.bookmarks) { bookmark in
                    HStack(spacing: 8) {
                        Button {
                            model.navigate(to: bookmark)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(model.bookmarkTitle(bookmark))
                                    .font(.headline)
                                    .lineLimit(2)
                                HStack(spacing: 4) {
                                    Text(model.chapterTitle(for: bookmark))
                                    if let fraction = bookmark.fractionInChapter {
                                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "\(model.bookmarkTitle(bookmark)), \(model.chapterTitle(for: bookmark))"
                        )
                        .accessibilityIdentifier(
                            "reader-bookmark-location-\(bookmark.id.databaseString)"
                        )

                        Button {
                            bookmarkPendingDeletion = bookmark
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Delete Bookmark")
                        .accessibilityLabel("Delete bookmark at \(model.bookmarkTitle(bookmark))")
                        .accessibilityIdentifier(
                            "reader-bookmark-delete-\(bookmark.id.databaseString)"
                        )
                    }
                }
            }
        }
        .background {
            ReaderFocusRequester(
                area: .sidebar,
                isActive: focusedArea == .sidebar,
                requestID: focusRequestID
            )
        }
        .accessibilityLabel("Bookmarks")
        .accessibilityIdentifier("reader-bookmarks")
    }

    private var chapterSelection: Binding<Chapter.ID?> {
        Binding(
            get: { model.selectedChapterID },
            set: { chapterID in
                guard let chapterID else { return }
                model.selectChapter(chapterID)
            }
        )
    }

    @ViewBuilder
    private func readerContent(
        preferences: ReaderPreferences,
        renderRequestID: ReaderRenderRequestID
    ) -> some View {
        if let errorMessage = model.errorMessage {
            ContentUnavailableView {
                Label("Reader Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            }
            .accessibilityIdentifier("reader-error")
        } else if model.isLoadingBook || model.isLoadingChapters {
            ContentUnavailableView {
                ProgressView()
                Text("Opening Book")
            }
            .accessibilityIdentifier("reader-loading")
        } else if model.chapters.isEmpty {
            ContentUnavailableView {
                Label("No Chapters", systemImage: "text.book.closed")
            } description: {
                Text("Use Edit Book to import or replace this book's content.")
            }
            .accessibilityIdentifier("reader-no-chapters")
        } else if let renderErrorMessage = model.renderErrorMessage {
            ContentUnavailableView {
                Label("Chapter Could Not Be Rendered", systemImage: "exclamationmark.triangle")
            } description: {
                Text(renderErrorMessage)
            } actions: {
                Button("Try Again") {
                    Task { await model.renderSelectedChapter(preferences: preferences) }
                }
                .accessibilityIdentifier("reader-render-retry")
            }
            .accessibilityIdentifier("reader-render-error")
        } else if let renderedChapter = model.renderedChapter,
                  renderedChapter.chapterID == model.selectedChapterID {
            ZStack(alignment: .topTrailing) {
                ReaderWebView(
                    document: renderedChapter.document,
                    loadID: renderRequestID,
                    assetLoader: model.assetLoader,
                    restorationLocation: model.restorationLocation(for: renderedChapter),
                    bookmarkNavigation: model.resolvedBookmarkNavigation(for: renderedChapter),
                    shouldFocus: focusedArea == .readerPanel,
                    focusRequestID: focusRequestID,
                    onLocationChange: { location in
                        model.recordLocation(location, chapterID: renderedChapter.chapterID)
                    },
                    onBookmarkNavigationCompleted: { navigationID in
                        model.completeBookmarkNavigation(id: navigationID)
                    }
                )

                if !renderedChapter.issues.isEmpty {
                    Label(
                        renderedChapter.issues.count == 1
                            ? "1 content warning"
                            : "\(renderedChapter.issues.count) content warnings",
                        systemImage: "exclamationmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(10)
                    .help(renderedChapter.issues.map(\.message).joined(separator: "\n"))
                    .accessibilityIdentifier("reader-content-warning")
                }
            }
        } else {
            ContentUnavailableView {
                ProgressView()
                Text("Rendering Chapter")
            }
            .accessibilityIdentifier("reader-rendering")
        }
    }

    @ToolbarContentBuilder
    private func readerToolbar(settings: ReaderSettingsStore) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.movePrevious()
            } label: {
                Label("Previous Chapter", systemImage: "chevron.left")
            }
            .disabled(!model.canMovePrevious)
            .help("Previous Chapter (Left Arrow)")
            .accessibilityIdentifier("reader-previous-chapter")

            chapterJumpMenu

            Button {
                model.moveNext()
            } label: {
                Label("Next Chapter", systemImage: "chevron.right")
            }
            .disabled(!model.canMoveNext)
            .help("Next Chapter (Right Arrow)")
            .accessibilityIdentifier("reader-next-chapter")

            Button(action: addBookmark) {
                Label("Add Bookmark", systemImage: "bookmark")
            }
            .disabled(model.selectedChapter == nil || model.renderedChapter == nil)
            .help("Add Bookmark (B)")
            .accessibilityIdentifier("reader-add-bookmark")

            Button {
                isFindPresented.toggle()
            } label: {
                Label("Find in Book", systemImage: "magnifyingglass")
            }
            .disabled(model.chapters.isEmpty)
            .keyboardShortcut("f", modifiers: .command)
            .popover(isPresented: $isFindPresented, arrowEdge: .bottom) {
                ReaderBookFindView(
                    query: $findQuery,
                    chapters: model.chapters
                ) { chapterID in
                    model.selectChapter(chapterID)
                    isFindPresented = false
                }
            }
            .help("Find in Book (Command-F)")
            .accessibilityIdentifier("reader-find")

            Button {
                isAppearancePresented.toggle()
            } label: {
                Label("Reading Appearance", systemImage: "textformat.size")
            }
            .popover(isPresented: $isAppearancePresented, arrowEdge: .bottom) {
                ReaderAppearanceView(settings: settings)
            }
            .help("Reading Appearance")
            .accessibilityIdentifier("reader-appearance")
        }
    }

    private var chapterJumpMenu: some View {
        Menu {
            ForEach(model.chapters) { chapter in
                Button {
                    model.selectChapter(chapter.id)
                } label: {
                    if chapter.id == model.selectedChapterID {
                        Label(chapter.title, systemImage: "checkmark")
                    } else {
                        Text(chapter.title)
                    }
                }
            }
        } label: {
            VStack(spacing: 1) {
                Text(model.selectedChapter?.title ?? "Chapter")
                    .lineLimit(1)
                if let position = model.chapterPositionDescription {
                    Text(position)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 120, maxWidth: 220)
        }
        .menuStyle(.button)
        .disabled(model.chapters.isEmpty)
        .help("Jump to Chapter")
        .accessibilityIdentifier("reader-chapter-jump")
    }

    private var deleteBookmarkIsPresented: Binding<Bool> {
        Binding(
            get: { bookmarkPendingDeletion != nil },
            set: { isPresented in
                if !isPresented { bookmarkPendingDeletion = nil }
            }
        )
    }

    private func handleReaderKeyCommand(_ command: ReaderKeyCommand) -> Bool {
        switch command {
        case .addBookmark:
            addBookmark()
            return true
        case .toggleSidebar:
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            return true
        case .previousChapter:
            if model.canMovePrevious {
                model.movePrevious()
            }
            return true
        case .nextChapter:
            if model.canMoveNext {
                model.moveNext()
            }
            return true
        case .previousSidebarItem:
            guard focusedArea == .sidebar, sidebarMode == .contents else { return false }
            if model.canMovePrevious {
                model.movePrevious()
            }
            return true
        case .nextSidebarItem:
            guard focusedArea == .sidebar, sidebarMode == .contents else { return false }
            if model.canMoveNext {
                model.moveNext()
            }
            return true
        }
    }

    private func requestFocus(_ area: ReaderFocusArea) {
        focusedArea = area
        focusRequestID &+= 1
    }

    private func addBookmark() {
        guard model.selectedChapter != nil, model.renderedChapter != nil else { return }
        Task {
            if await model.addBookmark() {
                sidebarMode = .bookmarks
            }
        }
    }
}

enum ReaderFocusArea: Hashable {
    case sidebar
    case readerPanel
}

private enum ReaderSidebarMode: String, CaseIterable, Identifiable {
    case contents
    case bookmarks

    var id: Self { self }

    var title: String {
        switch self {
        case .contents:
            "Contents"
        case .bookmarks:
            "Bookmarks"
        }
    }
}

private struct ReaderBookFindView: View {
    @Binding var query: String
    let chapters: [Chapter]
    let selectChapter: (Chapter.ID) -> Void

    @FocusState private var isSearchFocused: Bool
    @State private var searchService = ReaderBookSearchService()
    @State private var results: [ReaderBookSearchResult] = []
    @State private var isSearching = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchRequest: ReaderBookSearchRequestID {
        ReaderBookSearchRequestID(
            query: trimmedQuery,
            chapters: chapters.map {
                ReaderBookSearchChapterRevision(
                    id: $0.id,
                    title: $0.title,
                    renderRevision: $0.renderRevision
                )
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Find in Book", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .accessibilityIdentifier("reader-find-field")

            if trimmedQuery.isEmpty {
                ContentUnavailableView {
                    Label("Find in Book", systemImage: "text.magnifyingglass")
                } description: {
                    Text("Search chapter titles and content in this book.")
                }
            } else if isSearching {
                ContentUnavailableView {
                    ProgressView()
                    Text("Searching Book")
                }
                .accessibilityIdentifier("reader-find-searching")
            } else if results.isEmpty {
                ContentUnavailableView.search(text: trimmedQuery)
                    .accessibilityIdentifier("reader-find-no-results")
            } else {
                List(results) { result in
                    Button {
                        selectChapter(result.chapterID)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(result.chapterTitle)
                                    .font(.headline)
                                Spacer()
                                Text(result.matchCount == 1 ? "1 match" : "\(result.matchCount) matches")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(result.snippet)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("reader-find-result-\(result.chapterID.databaseString)")
                }
                .listStyle(.inset)
                .accessibilityIdentifier("reader-find-results")
            }
        }
        .padding(12)
        .frame(width: 420, height: 360)
        .accessibilityIdentifier("reader-find-in-book")
        .onAppear {
            isSearchFocused = true
        }
        .task(id: searchRequest) {
            guard !trimmedQuery.isEmpty else {
                results = []
                isSearching = false
                return
            }

            isSearching = true
            let foundResults = await searchService.results(
                for: trimmedQuery,
                in: chapters
            )
            guard !Task.isCancelled else { return }
            results = foundResults
            isSearching = false
        }
    }
}

private struct ReaderBookSearchRequestID: Hashable {
    let query: String
    let chapters: [ReaderBookSearchChapterRevision]
}

private struct ReaderBookSearchChapterRevision: Hashable {
    let id: Chapter.ID
    let title: String
    let renderRevision: Int
}

private struct ReaderAppearanceView: View {
    @Bindable var settings: ReaderSettingsStore

    var body: some View {
        Form {
            Picker("Font", selection: $settings.fontFamily) {
                ForEach(ReaderFontFamily.allCases, id: \.self) { family in
                    Text(family.title).tag(family)
                }
            }

            LabeledContent("Text Size") {
                HStack {
                    Slider(
                        value: $settings.fontSize,
                        in: ReaderPreferences.fontSizeRange,
                        step: 1
                    )
                    Text("\(Int(settings.fontSize.rounded())) pt")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }

            LabeledContent("Line Spacing") {
                HStack {
                    Slider(
                        value: $settings.lineHeight,
                        in: ReaderPreferences.lineHeightRange,
                        step: 0.05
                    )
                    Text(settings.lineHeight.formatted(.number.precision(.fractionLength(2))))
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            }

            LabeledContent("Page Width") {
                HStack {
                    Slider(
                        value: $settings.contentWidth,
                        in: ReaderPreferences.contentWidthRange,
                        step: 1
                    )
                    Text("\(Int(settings.contentWidth.rounded()))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }

            Picker("Theme", selection: $settings.theme) {
                ForEach(ReaderTheme.allCases, id: \.self) { theme in
                    Text(theme.title).tag(theme)
                }
            }

            HStack {
                Spacer()
                Button("Restore Defaults") {
                    settings.reset()
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 360)
        .accessibilityIdentifier("reader-appearance-controls")
    }
}
