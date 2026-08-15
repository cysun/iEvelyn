import AppKit
import SwiftUI

struct BookCoverArtwork: View {
    let book: LibraryBook
    let loadImageData: ((Asset) async throws -> Data)?
    let onLoadError: ((Error) -> Void)?
    @State private var loadedAssetID: UUID?
    @State private var imageData: Data?

    init(
        book: LibraryBook,
        loadImageData: ((Asset) async throws -> Data)? = nil,
        onLoadError: ((Error) -> Void)? = nil
    ) {
        self.book = book
        self.loadImageData = loadImageData
        self.onLoadError = onLoadError
    }

    var body: some View {
        Group {
            // SwiftUI has no Data-backed image initializer on macOS. AppKit is
            // isolated here solely to decode the small, generated thumbnail.
            if let imageData = displayedImageData, let image = NSImage(data: imageData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                generatedArtwork
            }
        }
        .aspectRatio(LibraryDesignTokens.coverAspectRatio, contentMode: .fit)
        .contentShape(Rectangle())
        .clipShape(RoundedRectangle(cornerRadius: LibraryDesignTokens.coverCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: LibraryDesignTokens.coverCornerRadius)
                .strokeBorder(
                    Color.white.opacity(0.14),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.14), radius: 5, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cover for \(book.title)")
        .task(id: book.coverAsset?.id) {
            loadedAssetID = nil
            imageData = nil
            guard let asset = book.coverAsset, let loadImageData else { return }

            do {
                let loadedData = try await loadImageData(asset)
                try Task.checkCancellation()
                loadedAssetID = asset.id
                imageData = loadedData
            } catch is CancellationError {
                return
            } catch {
                onLoadError?(error)
            }
        }
    }

    private var displayedImageData: Data? {
        guard loadedAssetID == book.coverAsset?.id else { return nil }
        return imageData
    }

    private var generatedArtwork: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: LibraryDesignTokens.coverCornerRadius)
                .fill(
                    LinearGradient(
                        colors: book.coverStyle.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            decorativePattern

            VStack(alignment: .leading, spacing: 5) {
                Text(book.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(4)

                Text(book.authorLine.uppercased())
                    .font(.caption2.weight(.medium))
                    .lineLimit(2)
                    .opacity(0.82)
            }
            .foregroundStyle(.white)
            .padding(14)
        }
    }

    private var decorativePattern: some View {
        GeometryReader { proxy in
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: proxy.size.width * 0.85)
                .offset(x: proxy.size.width * 0.42, y: -proxy.size.height * 0.12)

            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 2)
                .frame(width: proxy.size.width * 0.54)
                .offset(x: -proxy.size.width * 0.13, y: proxy.size.height * 0.16)
        }
        .accessibilityHidden(true)
    }
}

private extension BookCoverStyle {
    var gradientColors: [Color] {
        switch self {
        case .ember:
            [Color(red: 0.63, green: 0.12, blue: 0.14), Color(red: 0.93, green: 0.44, blue: 0.20)]
        case .forest:
            [Color(red: 0.08, green: 0.34, blue: 0.24), Color(red: 0.38, green: 0.64, blue: 0.38)]
        case .midnight:
            [Color(red: 0.08, green: 0.12, blue: 0.31), Color(red: 0.29, green: 0.32, blue: 0.62)]
        case .moss:
            [Color(red: 0.28, green: 0.32, blue: 0.13), Color(red: 0.64, green: 0.58, blue: 0.26)]
        case .ocean:
            [Color(red: 0.03, green: 0.31, blue: 0.44), Color(red: 0.21, green: 0.67, blue: 0.70)]
        case .plum:
            [Color(red: 0.32, green: 0.10, blue: 0.36), Color(red: 0.69, green: 0.31, blue: 0.57)]
        case .slate:
            [Color(red: 0.18, green: 0.23, blue: 0.29), Color(red: 0.47, green: 0.53, blue: 0.58)]
        case .sunset:
            [Color(red: 0.50, green: 0.16, blue: 0.42), Color(red: 0.96, green: 0.55, blue: 0.31)]
        }
    }
}
