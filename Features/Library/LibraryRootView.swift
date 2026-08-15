import SwiftUI

struct LibraryRootView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Welcome to iEvelyn")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("library-root-title")

            Text("Your personal ebook library will appear here.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("library-root")
    }
}

#Preview {
    LibraryRootView()
        .frame(width: 900, height: 600)
}
