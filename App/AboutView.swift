import AppKit
import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            // SwiftUI does not expose the running app's rendered icon. AppKit
            // is isolated to this read-only bridge for the About window.
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 104, height: 104)
                .accessibilityHidden(true)

            Text(AppIdentity.displayName)
                .font(.title.bold())

            Text(AppIdentity.summary)
                .foregroundStyle(.secondary)

            Text(AppIdentity.versionAndBuild)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("about-version")

            Text(AppIdentity.copyright)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("about-copyright")
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(width: 380)
    }
}

#Preview {
    AboutView()
}
