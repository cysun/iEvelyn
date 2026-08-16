import Foundation
import Observation

@MainActor
@Observable
final class ChapterManagementViewModel {
    let bookID: UUID
    private let repository: any LibraryRepository
    private let now: @Sendable () -> Date
    private var isObserving = false
    private var pendingSelectionID: UUID?

    private(set) var chapters: [Chapter] = []
    private(set) var isLoading = true
    private(set) var isPerformingOperation = false
    private(set) var errorMessage: String?
    private(set) var deletionToUndo: ChapterDeletion?
    var selectedChapterID: UUID?
    var alert: ChapterManagementAlert?

    init(
        bookID: UUID,
        repository: any LibraryRepository,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.bookID = bookID
        self.repository = repository
        self.now = now
    }

    var selectedChapter: Chapter? {
        guard let selectedChapterID else { return nil }
        return chapters.first { $0.id == selectedChapterID }
    }

    var summary: ChapterCollectionSummary {
        ChapterCollectionSummary(chapters: chapters)
    }

    var canMoveSelectionUp: Bool {
        guard let selectedChapterID,
              let index = chapters.firstIndex(where: { $0.id == selectedChapterID }) else {
            return false
        }
        return index > chapters.startIndex
    }

    var canMoveSelectionDown: Bool {
        guard let selectedChapterID,
              let index = chapters.firstIndex(where: { $0.id == selectedChapterID }) else {
            return false
        }
        return index < chapters.index(before: chapters.endIndex)
    }

    func observeChapters() async {
        guard !isObserving else { return }
        isObserving = true
        isLoading = chapters.isEmpty
        errorMessage = nil
        defer { isObserving = false }

        do {
            for try await observedChapters in repository.observeChapters(forBookID: bookID) {
                chapters = observedChapters
                reconcileSelection()
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

    func select(_ chapterID: UUID) {
        guard chapters.contains(where: { $0.id == chapterID }) else { return }
        selectedChapterID = chapterID
        pendingSelectionID = nil
    }

    @discardableResult
    func createChapter(title: String) async -> Bool {
        guard let chapterID = await performOperation(
            errorTitle: "Could Not Add Chapter",
            operation: {
                try await repository.createChapter(bookID: bookID, title: title, at: now())
            }
        ) else {
            return false
        }
        requestSelection(chapterID)
        return true
    }

    @discardableResult
    func renameSelectedChapter(to title: String) async -> Bool {
        guard let selectedChapterID else { return false }
        return await performOperation(
            errorTitle: "Could Not Rename Chapter",
            operation: {
                try await repository.renameChapter(id: selectedChapterID, title: title, at: now())
            }
        ) != nil
    }

    @discardableResult
    func duplicateSelectedChapter() async -> Bool {
        guard let selectedChapterID else { return false }
        guard let duplicateID = await performOperation(
            errorTitle: "Could Not Duplicate Chapter",
            operation: {
                try await repository.duplicateChapter(id: selectedChapterID, at: now())
            }
        ) else {
            return false
        }
        requestSelection(duplicateID)
        return true
    }

    @discardableResult
    func deleteChapter(id: UUID) async -> Bool {
        guard let deletedIndex = chapters.firstIndex(where: { $0.id == id }) else {
            return false
        }
        guard let deletion = await performOperation(
            errorTitle: "Could Not Delete Chapter",
            operation: {
                try await repository.deleteChapter(id: id, at: now())
            }
        ) else {
            return false
        }

        deletionToUndo = deletion
        let remainingChapters = chapters.filter { $0.id != id }
        if remainingChapters.isEmpty {
            selectedChapterID = nil
        } else {
            selectedChapterID = remainingChapters[min(deletedIndex, remainingChapters.count - 1)].id
        }
        pendingSelectionID = nil
        return true
    }

    @discardableResult
    func undoLastDeletion() async -> Bool {
        guard let deletionToUndo else { return false }
        let restored = await performOperation(
            errorTitle: "Could Not Restore Chapter",
            operation: {
                try await repository.restoreChapterDeletion(deletionToUndo, at: now())
            }
        ) != nil
        if restored {
            self.deletionToUndo = nil
            requestSelection(deletionToUndo.chapter.id)
        }
        return restored
    }

    @discardableResult
    func moveSelectedChapter(by offset: Int) async -> Bool {
        guard let selectedChapterID,
              let currentIndex = chapters.firstIndex(where: { $0.id == selectedChapterID }) else {
            return false
        }
        let destinationIndex = currentIndex + offset
        guard chapters.indices.contains(destinationIndex) else { return false }

        var orderedIDs = chapters.map(\.id)
        orderedIDs.swapAt(currentIndex, destinationIndex)
        return await persistOrder(orderedIDs, retainingSelection: selectedChapterID)
    }

    @discardableResult
    func moveChapter(_ draggedChapterID: UUID, before targetChapterID: UUID) async -> Bool {
        guard draggedChapterID != targetChapterID,
              chapters.contains(where: { $0.id == draggedChapterID }) else {
            return false
        }

        var orderedIDs = chapters.map(\.id)
        guard let draggedIndex = orderedIDs.firstIndex(of: draggedChapterID) else { return false }
        orderedIDs.remove(at: draggedIndex)
        guard let targetIndex = orderedIDs.firstIndex(of: targetChapterID) else { return false }
        orderedIDs.insert(draggedChapterID, at: targetIndex)
        return await persistOrder(orderedIDs, retainingSelection: draggedChapterID)
    }

    private func persistOrder(_ orderedIDs: [UUID], retainingSelection selectionID: UUID) async -> Bool {
        let reordered = await performOperation(
            errorTitle: "Could Not Reorder Chapters",
            operation: {
                try await repository.reorderChapters(
                    bookID: bookID,
                    orderedChapterIDs: orderedIDs,
                    at: now()
                )
            }
        ) != nil
        if reordered {
            requestSelection(selectionID)
        }
        return reordered
    }

    private func requestSelection(_ chapterID: UUID) {
        selectedChapterID = chapterID
        pendingSelectionID = chapterID
    }

    private func reconcileSelection() {
        if let pendingSelectionID,
           chapters.contains(where: { $0.id == pendingSelectionID }) {
            selectedChapterID = pendingSelectionID
            self.pendingSelectionID = nil
            return
        }

        if let selectedChapterID,
           chapters.contains(where: { $0.id == selectedChapterID }) {
            return
        }
        selectedChapterID = chapters.first?.id
    }

    private func performOperation<Value>(
        errorTitle: String,
        operation: () async throws -> Value
    ) async -> Value? {
        guard !isPerformingOperation else { return nil }
        isPerformingOperation = true
        defer { isPerformingOperation = false }

        do {
            return try await operation()
        } catch is CancellationError {
            return nil
        } catch {
            alert = ChapterManagementAlert(
                title: errorTitle,
                message: error.localizedDescription
            )
            return nil
        }
    }
}

nonisolated struct ChapterManagementAlert: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let message: String
}
