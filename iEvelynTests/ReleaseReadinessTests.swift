import Foundation
import Testing
@testable import iEvelyn

@Suite("Release readiness")
struct ReleaseReadinessTests {
    @Test("About content uses the packaged version, build, and copyright")
    @MainActor
    func aboutContent() {
        let info = [
            "CFBundleShortVersionString": "1.1",
            "CFBundleVersion": "2",
            "NSHumanReadableCopyright": "Copyright © 2026 Chengyu Sun. All rights reserved.",
        ]

        #expect(AppIdentity.versionAndBuild(infoDictionary: info) == "Version 1.1 (2)")
        #expect(
            AppIdentity.copyright(infoDictionary: info)
                == "Copyright © 2026 Chengyu Sun. All rights reserved."
        )
        #expect(AppIdentity.versionAndBuild(infoDictionary: [:]) == "Version 1.1 (2)")
        #expect(AppIdentity.copyright(infoDictionary: [:]) == AppIdentity.fallbackCopyright)
    }

    @Test("Large library filtering and sorting stays within the release budget")
    func largeLibraryQueryPerformance() {
        let referenceDate = Date(timeIntervalSince1970: 1_786_874_722)
        let books = (0..<20_000).map { index in
            let id = UUID()
            return LibraryBook(
                id: id,
                title: "Book \(20_000 - index)",
                subtitle: index.isMultiple(of: 3) ? "A subtitle" : nil,
                authors: ["Author \(index % 400)"],
                summary: "Representative local-library metadata.",
                tags: ["Tag \(index % 40)"],
                dateAdded: referenceDate.addingTimeInterval(TimeInterval(-index * 60)),
                isFavorite: index.isMultiple(of: 7),
                isCurrentlyReading: index.isMultiple(of: 11),
                readingProgress: index.isMultiple(of: 11) ? 0.5 : nil,
                isTrashed: index.isMultiple(of: 97),
                coverStyle: .derived(from: id)
            )
        }
        let clock = ContinuousClock()
        let start = clock.now
        let results = LibraryQuery(
            destination: .favorites,
            searchText: "author 12",
            sortOrder: .author,
            referenceDate: referenceDate
        ).apply(to: books)
        let elapsed = start.duration(to: clock.now)

        #expect(!results.isEmpty)
        #expect(elapsed < .seconds(5))
    }

    @Test("Representative long-form Markdown renders within the release budget")
    func longFormRenderingPerformance() async throws {
        let paragraphs = (0..<2_000).map { index in
            "Paragraph \(index) contains **emphasis**, 中文内容, and a [safe link](https://example.com)."
        }
        let source = "# Long Chapter\n\n" + paragraphs.joined(separator: "\n\n")
        let renderer = MarkdownRenderingService(cacheCapacity: 2)
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await renderer.render(
            MarkdownRenderRequest(
                markdown: source,
                bookID: UUID(),
                mode: .readerHTML,
                documentTitle: "Long Chapter"
            )
        )
        let elapsed = start.duration(to: clock.now)

        #expect(result.blocks.count >= 2_000)
        #expect(result.document.contains("Paragraph 1999"))
        #expect(elapsed < .seconds(8))
    }
}
