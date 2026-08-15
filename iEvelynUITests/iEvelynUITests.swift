import XCTest

final class iEvelynUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRootViewAppears() throws {
        let app = launchApplication(seedSampleLibrary: true)

        let sidebar = app.descendants(matching: .any)["library-sidebar"]
        XCTAssertTrue(
            sidebar.waitForExistence(timeout: 10),
            "The iEvelyn library sidebar should be visible after launch."
        )
        let grid = app.descendants(matching: .any)["library-grid"]
        XCTAssertTrue(
            grid.waitForExistence(timeout: 5),
            "The library should initially use its grid presentation."
        )
        XCTAssertGreaterThan(
            grid.frame.width,
            sidebar.frame.width * 2,
            "The browsing canvas should occupy the main window instead of a narrow middle column."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["library-detail-empty"].exists,
            "The main window should not reserve a persistent book-detail column."
        )
    }

    @MainActor
    func testBookActivationUsesReaderSeamAndItemMoreMenu() throws {
        let app = launchApplication(seedSampleLibrary: true)

        let book = app.buttons["Kindred, by Octavia E. Butler"]
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.click()

        XCTAssertTrue(app.staticTexts["Reader Not Available Yet"].waitForExistence(timeout: 5))
        app.buttons["OK"].click()
        XCTAssertTrue(app.descendants(matching: .any)["library-grid"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["library-detail-empty"].exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["library-book-actions"].exists,
            "Book management should not depend on a toolbar selection."
        )

        let actions = app.descendants(matching: .any)["Actions for Kindred"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        XCTAssertTrue(actions.isEnabled)
        actions.click()
        app.menuItems["Book Info…"].click()

        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Octavia E. Butler"].exists)
        app.buttons["Close"].click()
        XCTAssertTrue(app.descendants(matching: .any)["library-grid"].waitForExistence(timeout: 5))
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
        let listBook = app.buttons["Kindred, by Octavia E. Butler"]
        XCTAssertTrue(listBook.waitForExistence(timeout: 5))
        listBook.click()
        XCTAssertTrue(app.staticTexts["Reader Not Available Yet"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["reader-unavailable-dismiss"].click()
        XCTAssertTrue(
            app.descendants(matching: .any)["Actions for Kindred"].waitForExistence(timeout: 5)
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
        XCTAssertFalse(app.descendants(matching: .any)["book-editor-language"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["book-editor-publisher"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["book-editor-publication-date-toggle"].exists)
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

        let bookActions = app.descendants(matching: .any)["Actions for Workflow Book"]
        XCTAssertTrue(bookActions.waitForExistence(timeout: 5))
        bookActions.click()
        app.menuItems["Book Info…"].click()

        let favorite = app.descendants(matching: .any)["book-toggle-favorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Library Details"].exists)
        XCTAssertFalse(app.staticTexts["Publication Details"].exists)
        XCTAssertTrue(app.staticTexts["Added"].exists)
        XCTAssertTrue(app.staticTexts["Updated"].exists)
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
        let editedBookActions = app.descendants(matching: .any)["Actions for Edited Workflow Book"]
        XCTAssertTrue(editedBookActions.waitForExistence(timeout: 5))
        editedBookActions.click()
        app.menuItems["Move to Trash"].click()

        let trash = app.descendants(matching: .any)["sidebar-trash"]
        XCTAssertTrue(trash.waitForExistence(timeout: 5))
        trash.click()
        XCTAssertTrue(editedBook.waitForExistence(timeout: 5))
        editedBookActions.click()
        app.menuItems["Restore"].click()
        XCTAssertTrue(app.staticTexts["Trash is Empty"].waitForExistence(timeout: 5))

        let allBooks = app.descendants(matching: .any)["sidebar-allBooks"]
        allBooks.click()
        XCTAssertTrue(editedBook.waitForExistence(timeout: 5))
        editedBookActions.click()
        app.menuItems["Move to Trash"].click()

        trash.click()
        XCTAssertTrue(editedBook.waitForExistence(timeout: 5))
        editedBookActions.click()
        app.menuItems["Delete Permanently…"].click()

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
