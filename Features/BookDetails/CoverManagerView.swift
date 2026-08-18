import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CoverManagerView: View {
    @Environment(\.dismiss) private var dismiss

    let book: LibraryBook
    let model: LibraryViewModel

    @State private var covers: [Asset]
    @State private var isImporterPresented = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var pendingRemoval: Asset?

    init(book: LibraryBook, model: LibraryViewModel) {
        self.book = book
        self.model = model
        _covers = State(initialValue: book.coverAssets)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if covers.isEmpty, !isWorking {
                    ContentUnavailableView {
                        Label("No Cover Images", systemImage: "photo.on.rectangle.angled")
                    } description: {
                        Text("Add one or more cover images for “\(book.title)”.")
                    } actions: {
                        Button("Add Cover Images…", systemImage: "photo.badge.plus") {
                            isImporterPresented = true
                        }
                        .accessibilityIdentifier("cover-manager-add-empty")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("cover-manager-empty")
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 180), spacing: 20)],
                            spacing: 24
                        ) {
                            ForEach(covers) { cover in
                                coverTile(cover)
                            }
                        }
                        .padding(24)
                    }
                    .accessibilityIdentifier("cover-manager-grid")
                }

                if let errorMessage {
                    Divider()
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .accessibilityIdentifier("cover-manager-error")
                }
            }
            .navigationTitle("Covers for \(book.title)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Updating covers")
                    }
                    Button("Add Cover Images…", systemImage: "photo.badge.plus") {
                        isImporterPresented = true
                    }
                    .disabled(isWorking)
                    .accessibilityIdentifier("cover-manager-add")
                }
            }
        }
        .frame(minWidth: 720, minHeight: 560)
        .disabled(isWorking)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.jpeg, .png, .heic],
            allowsMultipleSelection: true
        ) { result in
            receiveCoverSelection(result)
        }
        .confirmationDialog(
            "Remove this cover?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { cover in
            Button("Remove Cover", role: .destructive) {
                pendingRemoval = nil
                Task { await remove(cover) }
            }
            .accessibilityIdentifier("cover-manager-confirm-remove")
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { cover in
            Text(
                cover.isCurrentCover && covers.count > 1
                    ? "Another cover will become current automatically."
                    : "The stored image will be permanently removed from this book."
            )
        }
        .task { await refreshCovers() }
        .accessibilityIdentifier("cover-manager")
    }

    private func coverTile(_ cover: Asset) -> some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                CoverManagerThumbnail(asset: cover) {
                    try await model.loadCoverImage(for: cover)
                }
                .frame(maxWidth: 190)

                if cover.isCurrentCover {
                    Label("Current", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                        .padding(8)
                        .accessibilityIdentifier("cover-manager-current-\(cover.id.databaseString)")
                }
            }

            HStack {
                if !cover.isCurrentCover {
                    Button("Make Current") {
                        Task { await makeCurrent(cover) }
                    }
                    .accessibilityIdentifier("cover-manager-make-current-\(cover.id.databaseString)")
                }

                Spacer()

                Button("Remove", systemImage: "trash", role: .destructive) {
                    pendingRemoval = cover
                }
                .labelStyle(.iconOnly)
                .help("Remove Cover")
                .accessibilityLabel("Remove cover")
                .accessibilityIdentifier("cover-manager-remove-\(cover.id.databaseString)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cover-manager-cover-\(cover.id.databaseString)")
    }

    private func receiveCoverSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            Task { await add(urls) }
        case .failure(let error):
            guard (error as NSError).code != NSUserCancelledError else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func add(_ sourceURLs: [URL]) async {
        isWorking = true
        errorMessage = nil
        do {
            try await model.addCovers(to: book.id, from: sourceURLs)
        } catch is CancellationError {
            isWorking = false
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshCovers(clearError: false)
        isWorking = false
    }

    private func makeCurrent(_ cover: Asset) async {
        isWorking = true
        errorMessage = nil
        do {
            try await model.makeCurrentCover(cover.id, for: book.id)
        } catch is CancellationError {
            isWorking = false
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshCovers(clearError: false)
        isWorking = false
    }

    private func remove(_ cover: Asset) async {
        isWorking = true
        errorMessage = nil
        do {
            try await model.removeCover(cover.id, from: book.id)
        } catch is CancellationError {
            isWorking = false
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshCovers(clearError: false)
        isWorking = false
    }

    private func refreshCovers(clearError: Bool = true) async {
        if clearError { errorMessage = nil }
        do {
            covers = try await model.covers(for: book.id)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CoverManagerThumbnail: View {
    let asset: Asset
    let load: () async throws -> Data

    @State private var imageData: Data?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let imageData, let image = NSImage(data: imageData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if loadFailed {
                ContentUnavailableView("Cover Unavailable", systemImage: "photo.badge.exclamationmark")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .aspectRatio(LibraryDesignTokens.coverAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: LibraryDesignTokens.coverCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: LibraryDesignTokens.coverCornerRadius)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .task(id: asset.id) {
            imageData = nil
            loadFailed = false
            do {
                imageData = try await load()
            } catch is CancellationError {
                return
            } catch {
                loadFailed = true
            }
        }
        .accessibilityLabel(asset.isCurrentCover ? "Current cover" : "Cover image")
    }
}
