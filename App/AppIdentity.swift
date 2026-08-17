import Foundation

enum AppIdentity {
    static let displayName = "iEvelyn"
    static let bundleIdentifier = "org.cysun.iEvelyn"
    static let summary = "A native personal ebook library for macOS."
    static let fallbackCopyright = "Copyright © 2026 Chengyu Sun. All rights reserved."

    static var versionAndBuild: String {
        versionAndBuild(infoDictionary: Bundle.main.infoDictionary)
    }

    static var copyright: String {
        copyright(infoDictionary: Bundle.main.infoDictionary)
    }

    static func versionAndBuild(infoDictionary: [String: Any]?) -> String {
        let version = stringValue(
            forKey: "CFBundleShortVersionString",
            in: infoDictionary
        ) ?? "1.0"
        let build = stringValue(forKey: "CFBundleVersion", in: infoDictionary) ?? "1"
        return "Version \(version) (\(build))"
    }

    static func copyright(infoDictionary: [String: Any]?) -> String {
        stringValue(forKey: "NSHumanReadableCopyright", in: infoDictionary)
            ?? fallbackCopyright
    }

    private static func stringValue(
        forKey key: String,
        in infoDictionary: [String: Any]?
    ) -> String? {
        guard let value = infoDictionary?[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
