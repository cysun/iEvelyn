import Testing
@testable import iEvelyn

@Suite("Application bootstrap")
struct ApplicationBootstrapTests {
    @MainActor
    @Test("Product identity uses the approved values")
    func productIdentityUsesApprovedValues() {
        #expect(AppIdentity.displayName == "iEvelyn")
        #expect(AppIdentity.bundleIdentifier == "org.cysun.iEvelyn")
    }

    @MainActor
    @Test("The root view can be constructed")
    func rootViewCanBeConstructed() {
        let rootView = LibraryRootView(
            repository: PreviewLibraryRepository(books: [])
        )

        #expect(String(describing: type(of: rootView)) == "LibraryRootView")
    }

    @Test("UI tests always select an in-memory database")
    func uiTestsSelectInMemoryDatabase() {
        let configuration = LibraryLaunchConfiguration(
            arguments: [
                "iEvelyn",
                LibraryLaunchConfiguration.uiTestingArgument,
                LibraryLaunchConfiguration.seedSampleLibraryArgument
            ]
        )

        #expect(configuration.mode == .testingInMemory(seedSampleLibrary: true))
    }
}
