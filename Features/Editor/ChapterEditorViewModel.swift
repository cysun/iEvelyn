import Foundation
import Observation

nonisolated enum ChapterEditorSaveState: Equatable, Sendable {
    case saved
    case waiting
    case saving
    case failed(message: String)
    case conflict(message: String)
}

private actor ChapterTextMetricsCalculator {
    func metrics(for markdown: String) -> ChapterTextMetrics {
        ChapterTextMetrics(markdown: markdown)
    }
}

@MainActor
@Observable
final class ChapterEditorViewModel {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private struct ActiveSave {
        let token: Int
        let chapterID: UUID
        let markdown: String
        let task: Task<Chapter, Error>
    }

    private let repository: any LibraryRepository
    private let importer: any ChapterSourceImporting
    private let now: @Sendable () -> Date
    private let debounceDuration: Duration
    private let sleep: Sleep
    private let metricsCalculator = ChapterTextMetricsCalculator()

    private(set) var activeChapterID: UUID?
    private(set) var markdown = ""
    private(set) var metrics = ChapterTextMetrics.zero
    private(set) var saveState = ChapterEditorSaveState.saved
    private(set) var importErrorMessage: String?
    private(set) var isImporting = false
    private(set) var previewGeneration = 0

    private var persistedMarkdown = ""
    private var expectedRenderRevision = 0
    private var conflictingChapter: Chapter?
    private var debounceTask: Task<Void, Never>?
    private var debounceToken = 0
    private var metricsTask: Task<Void, Never>?
    private var metricsToken = 0
    private var activeSave: ActiveSave?
    private var nextSaveToken = 0

    init(
        repository: any LibraryRepository,
        importer: any ChapterSourceImporting = ChapterSourceImporter(),
        now: @escaping @Sendable () -> Date = { .now },
        debounceDuration: Duration = .milliseconds(650),
        sleep: @escaping Sleep = { duration in
            try await ContinuousClock().sleep(for: duration)
        }
    ) {
        self.repository = repository
        self.importer = importer
        self.now = now
        self.debounceDuration = debounceDuration
        self.sleep = sleep
    }

    var hasUnsavedChanges: Bool {
        activeSave != nil || markdown != persistedMarkdown
    }

    var shouldPreventDismissal: Bool {
        hasUnsavedChanges || isImporting
    }

    var canRetrySave: Bool {
        if case .failed = saveState { return true }
        return false
    }

    var hasConflict: Bool {
        if case .conflict = saveState { return true }
        return false
    }

    func activate(_ chapter: Chapter) async -> Bool {
        if activeChapterID == chapter.id {
            receiveObservedChapter(chapter)
            return true
        }
        guard await flushPendingSave() else { return false }
        load(chapter)
        return true
    }

    func receiveObservedChapter(_ chapter: Chapter) {
        guard activeChapterID == chapter.id else { return }
        guard activeSave == nil,
              markdown == persistedMarkdown,
              chapter.renderRevision != expectedRenderRevision else {
            return
        }
        load(chapter)
    }

    func updateMarkdown(_ newMarkdown: String) {
        guard activeChapterID != nil, markdown != newMarkdown else { return }
        markdown = newMarkdown
        previewGeneration &+= 1
        conflictingChapter = nil
        importErrorMessage = nil
        scheduleMetrics(for: newMarkdown)

        if newMarkdown == persistedMarkdown, activeSave == nil {
            debounceTask?.cancel()
            debounceTask = nil
            saveState = .saved
        } else {
            saveState = activeSave == nil ? .waiting : .saving
            scheduleAutosave()
        }
    }

    func replaceMarkdown(
        with newMarkdown: String,
        undoManager: UndoManager?,
        actionName: String
    ) {
        let previousMarkdown = markdown
        guard previousMarkdown != newMarkdown else { return }

        let openedUndoGroup = undoManager?.groupingLevel == 0
        if openedUndoGroup {
            undoManager?.beginUndoGrouping()
        }
        undoManager?.registerUndo(withTarget: self) { target in
            target.replaceMarkdown(
                with: previousMarkdown,
                undoManager: undoManager,
                actionName: actionName
            )
        }
        undoManager?.setActionName(actionName)
        if openedUndoGroup {
            undoManager?.endUndoGrouping()
        }
        updateMarkdown(newMarkdown)
    }

    func importChapterSource(from sourceURL: URL, undoManager: UndoManager?) async {
        isImporting = true
        importErrorMessage = nil
        defer { isImporting = false }

        do {
            let importedMarkdown = try await importer.loadUTF8Text(from: sourceURL)
            try Task.checkCancellation()
            replaceMarkdown(
                with: importedMarkdown,
                undoManager: undoManager,
                actionName: "Import Chapter Source"
            )
        } catch is CancellationError {
            return
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    func reportImportFailure(_ error: Error) {
        importErrorMessage = error.localizedDescription
    }

    @discardableResult
    func flushPendingSave() async -> Bool {
        debounceTask?.cancel()
        debounceTask = nil

        while true {
            if let save = activeSave {
                let result = await save.task.result
                finish(save: save, result: result)
                if case .failed = saveState { return false }
                if case .conflict = saveState { return false }
                continue
            }

            guard markdown != persistedMarkdown else {
                debounceTask?.cancel()
                debounceTask = nil
                saveState = .saved
                return true
            }
            guard let chapterID = activeChapterID else { return true }

            nextSaveToken += 1
            let markdownToSave = markdown
            let renderRevision = expectedRenderRevision
            let saveDate = now()
            let save = ActiveSave(
                token: nextSaveToken,
                chapterID: chapterID,
                markdown: markdownToSave,
                task: Task {
                    try await repository.updateChapterMarkdown(
                        id: chapterID,
                        markdown: markdownToSave,
                        expectedRenderRevision: renderRevision,
                        at: saveDate
                    )
                }
            )
            activeSave = save
            saveState = .saving
        }
    }

    func retrySave() async {
        guard canRetrySave else { return }
        saveState = .waiting
        _ = await flushPendingSave()
    }

    func reloadStoredVersion() {
        guard let conflictingChapter else { return }
        load(conflictingChapter)
    }

    func overwriteStoredVersion() async {
        guard let conflictingChapter else { return }
        persistedMarkdown = conflictingChapter.markdown
        expectedRenderRevision = conflictingChapter.renderRevision
        self.conflictingChapter = nil
        saveState = .waiting
        _ = await flushPendingSave()
    }

    func discardUnsavedChanges() {
        guard activeSave == nil else { return }
        debounceTask?.cancel()
        debounceTask = nil
        markdown = persistedMarkdown
        previewGeneration &+= 1
        conflictingChapter = nil
        saveState = .saved
        scheduleMetrics(for: markdown, immediately: true)
    }

    private func load(_ chapter: Chapter) {
        debounceTask?.cancel()
        debounceTask = nil
        activeChapterID = chapter.id
        markdown = chapter.markdown
        previewGeneration &+= 1
        persistedMarkdown = chapter.markdown
        expectedRenderRevision = chapter.renderRevision
        conflictingChapter = nil
        importErrorMessage = nil
        saveState = .saved
        scheduleMetrics(for: chapter.markdown, immediately: true)
    }

    private func scheduleAutosave() {
        debounceTask?.cancel()
        debounceToken += 1
        let token = debounceToken
        let sleep = sleep
        let duration = debounceDuration

        debounceTask = Task { [weak self] in
            do {
                try await sleep(duration)
            } catch {
                return
            }
            guard let self, self.debounceToken == token else { return }
            self.debounceTask = nil
            _ = await self.flushPendingSave()
        }
    }

    private func scheduleMetrics(for markdown: String, immediately: Bool = false) {
        metricsTask?.cancel()
        metricsToken += 1
        let token = metricsToken
        let calculator = metricsCalculator

        metricsTask = Task { [weak self] in
            if !immediately {
                do {
                    try await ContinuousClock().sleep(for: .milliseconds(120))
                } catch {
                    return
                }
            }
            let metrics = await calculator.metrics(for: markdown)
            guard !Task.isCancelled, let self, self.metricsToken == token else { return }
            self.metrics = metrics
        }
    }

    private func finish(save: ActiveSave, result: Result<Chapter, Error>) {
        guard activeSave?.token == save.token else { return }
        activeSave = nil

        switch result {
        case .success(let storedChapter):
            guard activeChapterID == save.chapterID else { return }
            persistedMarkdown = storedChapter.markdown
            expectedRenderRevision = storedChapter.renderRevision
            conflictingChapter = nil
            saveState = markdown == persistedMarkdown ? .saved : .waiting

        case .failure(let error):
            if let conflict = error as? ChapterRevisionConflict {
                conflictingChapter = conflict.storedChapter
                saveState = .conflict(message: conflict.localizedDescription)
            } else if error is CancellationError {
                saveState = .failed(message: "The save was interrupted. Retry to preserve this draft.")
            } else {
                saveState = .failed(message: error.localizedDescription)
            }
        }
    }
}
