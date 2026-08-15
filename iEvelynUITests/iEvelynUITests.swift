import XCTest

final class iEvelynUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRootViewAppears() throws {
        let app = launchApplication(seedSampleLibrary: true)

        XCTAssertTrue(
            app.descendants(matching: .any)["library-sidebar"].waitForExistence(timeout: 10),
            "The iEvelyn library sidebar should be visible after launch."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["library-grid"].waitForExistence(timeout: 5),
            "The library should initially use its grid presentation."
        )
    }

    @MainActor
    func testSidebarNavigationAndEmptyState() throws {
        let app = launchApplication(seedSampleLibrary: true)

        let favorites = app.descendants(matching: .any)["sidebar-favorites"]
        XCTAssertTrue(favorites.waitForExistence(timeout: 10))
        favorites.click()

        let contentTitle = app.descendants(matching: .any)["library-content-title"]
        XCTAssertTrue(contentTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(contentTitle.label, "Favorites")

        let trash = app.descendants(matching: .any)["sidebar-trash"]
        XCTAssertTrue(trash.waitForExistence(timeout: 5))
        trash.click()

        XCTAssertTrue(
            app.descendants(matching: .any)["library-empty-state"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Trash is Empty"].exists)
    }

    @MainActor
    func testGridListSwitchingAndSearch() throws {
        let app = launchApplication(seedSampleLibrary: true)

        let listButton = app.descendants(matching: .any)["library-view-list"]
        XCTAssertTrue(listButton.waitForExistence(timeout: 10))
        listButton.click()

        XCTAssertTrue(
            app.descendants(matching: .any)["library-list"].waitForExistence(timeout: 5)
        )

        let gridButton = app.descendants(matching: .any)["library-view-grid"]
        XCTAssertTrue(gridButton.waitForExistence(timeout: 5))
        gridButton.click()

        let searchField = app.searchFields["Search Library"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.click()
        searchField.typeText("Kindred")

        XCTAssertTrue(
            app.buttons["Kindred, by Octavia E. Butler"].waitForExistence(timeout: 5)
        )

        searchField.typeKey("a", modifierFlags: .command)
        searchField.typeText("no matching book")

        XCTAssertTrue(
            app.descendants(matching: .any)["library-empty-state"].waitForExistence(timeout: 5)
        )

        app.buttons["Clear Search"].click()
        XCTAssertTrue(
            app.descendants(matching: .any)["library-grid"].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testAddEditFavoriteTrashRestoreAndPermanentDeleteWorkflow() throws {
        let app = launchApplication(seedSampleLibrary: false)

        let addBook = app.descendants(matching: .any)["library-add-book"]
        XCTAssertTrue(addBook.waitForExistence(timeout: 10))
        addBook.click()

        let save = app.descendants(matching: .any)["book-editor-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["book-editor-error"].waitForExistence(timeout: 5),
            "Saving empty metadata should present an actionable validation message."
        )

        let title = app.textFields["book-editor-title"]
        let firstAuthor = app.textFields["book-editor-author-0"]
        XCTAssertTrue(title.exists)
        XCTAssertTrue(firstAuthor.exists)
        title.click()
        title.typeText("Workflow Book")
        firstAuthor.click()
        firstAuthor.typeText("First Author")

        app.descendants(matching: .any)["book-editor-add-author"].click()
        let secondAuthor = app.textFields["book-editor-author-1"]
        XCTAssertTrue(secondAuthor.waitForExistence(timeout: 5))
        secondAuthor.click()
        secondAuthor.typeText("Second Author")
        save.click()

        let createdBook = app.buttons["Workflow Book, by First Author, Second Author"]
        XCTAssertTrue(createdBook.waitForExistence(timeout: 10))
        createdBook.click()

        let favorite = app.descendants(matching: .any)["book-toggle-favorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        favorite.click()
        XCTAssertTrue(app.buttons["Unfavorite"].waitForExistence(timeout: 5))

        app.descendants(matching: .any)["book-edit"].click()
        let editedTitle = app.textFields["book-editor-title"]
        XCTAssertTrue(editedTitle.waitForExistence(timeout: 5))
        editedTitle.click()
        editedTitle.typeKey("a", modifierFlags: .command)
        editedTitle.typeText("Edited Workflow Book")
        app.descendants(matching: .any)["book-editor-save"].click()

        let editedBook = app.buttons["Edited Workflow Book, by First Author, Second Author"]
        XCTAssertTrue(editedBook.waitForExistence(timeout: 10))
        editedBook.click()
        app.descendants(matching: .any)["book-move-to-trash"].click()

        let trash = app.descendants(matching: .any)["sidebar-trash"]
        XCTAssertTrue(trash.waitForExistence(timeout: 5))
        trash.click()
        XCTAssertTrue(editedBook.waitForExistence(timeout: 5))
        editedBook.click()
        app.descendants(matching: .any)["book-restore"].click()
        XCTAssertTrue(app.staticTexts["Trash is Empty"].waitForExistence(timeout: 5))

        let allBooks = app.descendants(matching: .any)["sidebar-allBooks"]
        allBooks.click()
        XCTAssertTrue(editedBook.waitForExistence(timeout: 5))
        editedBook.click()
        app.descendants(matching: .any)["book-move-to-trash"].click()

        trash.click()
        XCTAssertTrue(editedBook.waitForExistence(timeout: 5))
        editedBook.click()
        app.descendants(matching: .any)["book-delete-permanently"].click()

        let confirmDelete = app.descendants(matching: .any)["book-confirm-delete-permanently"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.click()
        XCTAssertTrue(app.staticTexts["Trash is Empty"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchApplication(seedSampleLibrary: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState",
            "YES",
            "--ui-testing"
        ]
        if seedSampleLibrary {
            app.launchArguments.append("--seed-sample-library")
        }
        app.launch()
        return app
    }
}
