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
    func testAboutIdentityAndAddBookKeyboardShortcut() throws {
        let app = launchApplication(seedSampleLibrary: false)
        XCTAssertTrue(
            app.descendants(matching: .any)["library-empty-state"].waitForExistence(timeout: 10)
        )

        let applicationMenu = app.menuBars.menuBarItems["iEvelyn"]
        applicationMenu.click()
        let aboutCommand = applicationMenu.menus.menuItems["About iEvelyn"]
        XCTAssertTrue(aboutCommand.waitForExistence(timeout: 5))
        aboutCommand.click()
        XCTAssertTrue(app.windows["About iEvelyn"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Version 1.0 (1)"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Copyright © 2026 Chengyu Sun. All rights reserved."].exists
        )
        app.typeKey("w", modifierFlags: .command)

        XCTAssertTrue(
            app.descendants(matching: .any)["library-empty-state"].waitForExistence(timeout: 5)
        )
        app.typeKey("n", modifierFlags: [.command, .shift])
        XCTAssertTrue(
            app.descendants(matching: .any)["book-editor-save"].waitForExistence(timeout: 5),
            "Command-Shift-N should open Add Book without requiring pointer input."
        )
        app.buttons["Cancel"].click()
    }

    @MainActor
    func testBookActivationOpensAndClosesDedicatedReaderWindow() throws {
        let app = launchApplication(seedSampleLibrary: true)

        let book = app.buttons["Kindred, by Octavia E. Butler"]
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.click()

        XCTAssertTrue(
            app.staticTexts["No Chapters"].waitForExistence(timeout: 10),
            "Book activation should open the dedicated reader window."
        )
        app.typeKey("w", modifierFlags: .command)

        XCTAssertTrue(app.descendants(matching: .any)["library-grid"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["library-detail-empty"].exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["library-book-actions"].exists,
            "Book management should not depend on a toolbar selection."
        )

        let actions = app.descendants(matching: .any)["Actions for Kindred"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        XCTAssertTrue(actions.isEnabled)
        actions.click()
        XCTAssertFalse(
            app.menuItems["Book Info…"].exists,
            "The book actions menu should no longer expose a separate Book Info sheet."
        )
        let editBook = app.menuItems["Edit Book…"]
        XCTAssertTrue(editBook.waitForExistence(timeout: 5))
        editBook.click()

        XCTAssertTrue(
            app.descendants(matching: .any)["book-editor-choose-cover"].waitForExistence(timeout: 5),
            "The unified Edit Book form should own cover changes."
        )
        XCTAssertTrue(app.descendants(matching: .any)["book-editor-content-mode"].exists)
        app.buttons["Cancel"].click()
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
        XCTAssertTrue(app.staticTexts["No Chapters"].waitForExistence(timeout: 10))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(
            app.descendants(matching: .any)["Actions for Kindred"].waitForExistence(timeout: 5)
        )

        let gridButton = app.descendants(matching: .any)["library-view-grid"]
        XCTAssertTrue(gridButton.waitForExistence(timeout: 5))
        gridButton.click()

        let searchField = app.searchFields["Search Library"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        app.typeKey("f", modifierFlags: .command)
        searchField.typeText("Kindred")

        XCTAssertTrue(
            app.descendants(matching: .any)["library-search-results"].waitForExistence(timeout: 5)
        )
        let titleResult = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "library-search-result-book:")
        )
        XCTAssertTrue(titleResult.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["library-search-scope"].exists)

        searchField.typeKey("a", modifierFlags: .command)
        searchField.typeText("no matching book")

        XCTAssertTrue(
            app.descendants(matching: .any)["library-search-empty"].waitForExistence(timeout: 5)
        )

        app.buttons["Clear Search"].click()
        XCTAssertTrue(
            app.descendants(matching: .any)["library-grid"].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testAddEditFavoriteTrashRestoreAndPermanentDeleteWorkflow() throws {
        let app = launchApplication(
            seedSampleLibrary: false,
            bookContent: """
            # Workflow Book
            ### First Author
            ### Second Author
            ## Opening

            Workflow content.
            """
        )

        let addBook = app.descendants(matching: .any)["library-add-book"]
        XCTAssertTrue(addBook.waitForExistence(timeout: 10))
        addBook.click()

        let save = app.descendants(matching: .any)["book-editor-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["book-editor-language"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["book-editor-publisher"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["book-editor-publication-date-toggle"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["book-editor-content-file"].exists)
        let showMoreOptions = app.descendants(matching: .any)["book-editor-show-more-options"]
        XCTAssertTrue(showMoreOptions.exists)
        XCTAssertFalse(app.textFields["book-editor-subtitle"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["book-editor-add-author"].exists)
        XCTAssertFalse(app.textViews["book-editor-summary"].exists)
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

        showMoreOptions.click()
        let subtitle = app.textFields["book-editor-subtitle"]
        XCTAssertTrue(subtitle.waitForExistence(timeout: 5))
        subtitle.click()
        subtitle.typeText("Expanded Subtitle")
        XCTAssertTrue(app.textViews["book-editor-summary"].exists)
        app.descendants(matching: .any)["book-editor-add-author"].click()
        let secondAuthor = app.textFields["book-editor-author-1"]
        XCTAssertTrue(secondAuthor.waitForExistence(timeout: 5))
        secondAuthor.click()
        secondAuthor.typeText("Second Author")
        app.descendants(matching: .any)["book-editor-add-tag"].click()
        let firstTag = app.textFields["book-editor-tag-0"]
        XCTAssertTrue(firstTag.waitForExistence(timeout: 5))
        firstTag.click()
        firstTag.typeText("Milestone")
        showMoreOptions.click()
        XCTAssertFalse(secondAuthor.exists)
        XCTAssertFalse(firstTag.exists)
        XCTAssertFalse(app.textFields["book-editor-subtitle"].exists)
        save.click()

        let createdBook = app.buttons["Workflow Book, by First Author, Second Author"]
        XCTAssertTrue(createdBook.waitForExistence(timeout: 10))

        let bookActions = app.descendants(matching: .any)["Actions for Workflow Book"]
        XCTAssertTrue(bookActions.waitForExistence(timeout: 5))
        bookActions.click()
        app.menuItems["Add to Favorites"].click()
        bookActions.click()
        XCTAssertTrue(app.menuItems["Remove from Favorites"].waitForExistence(timeout: 5))
        let editBook = app.menuItems["Edit Book…"]
        XCTAssertTrue(editBook.waitForExistence(timeout: 5))
        editBook.click()
        let editedTitle = app.textFields["book-editor-title"]
        XCTAssertTrue(editedTitle.waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.textFields["book-editor-author-1"].exists,
            "Edit Book should also open in the simple mode without discarding additional authors."
        )
        showMoreOptions.click()
        let reopenedSubtitle = app.textFields["book-editor-subtitle"]
        XCTAssertTrue(reopenedSubtitle.waitForExistence(timeout: 5))
        XCTAssertEqual(reopenedSubtitle.value as? String, "Expanded Subtitle")
        XCTAssertEqual(app.textFields["book-editor-author-1"].value as? String, "Second Author")
        XCTAssertEqual(app.textFields["book-editor-tag-0"].value as? String, "Milestone")
        showMoreOptions.click()
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
    func testAddBookContentAndCoverButtonsOpenFilePickers() throws {
        let app = launchApplication(seedSampleLibrary: false)

        app.descendants(matching: .any)["library-add-book"].click()

        let contentButton = app.descendants(matching: .any)["book-editor-choose-content"]
        XCTAssertTrue(contentButton.waitForExistence(timeout: 5))
        contentButton.click()

        let contentPicker = app.sheets.element(boundBy: 1)
        XCTAssertTrue(
            contentPicker.waitForExistence(timeout: 5),
            "Choose Content File should present the system file picker."
        )
        contentPicker.buttons["Cancel"].click()
        XCTAssertTrue(contentPicker.waitForNonExistence(timeout: 5))

        let coverButton = app.descendants(matching: .any)["book-editor-choose-cover"]
        XCTAssertTrue(coverButton.waitForExistence(timeout: 5))
        coverButton.click()

        let coverPicker = app.sheets.element(boundBy: 1)
        XCTAssertTrue(
            coverPicker.waitForExistence(timeout: 5),
            "Choose Cover should present the system file picker."
        )
        coverPicker.buttons["Cancel"].click()
        XCTAssertTrue(coverPicker.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testBookActionsExportEPUBWithSystemSavePanel() throws {
        let app = launchApplication(
            seedSampleLibrary: false,
            bookContent: """
            # Export Workflow
            ### Test Author
            ## Opening

            Exported content.
            """
        )

        app.descendants(matching: .any)["library-add-book"].click()
        let title = app.textFields["book-editor-title"]
        let author = app.textFields["book-editor-author-0"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.click()
        title.typeText("Export Workflow")
        author.click()
        author.typeText("Test Author")
        app.descendants(matching: .any)["book-editor-save"].click()

        let actions = app.descendants(matching: .any)["Actions for Export Workflow"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        actions.click()
        let export = app.menuItems["Export EPUB…"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        export.click()

        let savePanel = app.sheets.firstMatch
        XCTAssertTrue(
            savePanel.waitForExistence(timeout: 10),
            "Export EPUB should present the system file exporter after preflight succeeds."
        )
        XCTAssertTrue(savePanel.buttons["Cancel"].waitForExistence(timeout: 5))
        savePanel.buttons["Cancel"].click()
        XCTAssertTrue(savePanel.waitForNonExistence(timeout: 5))

        actions.click()
        let exportMarkdown = app.menuItems["Export Markdown…"]
        XCTAssertTrue(exportMarkdown.waitForExistence(timeout: 5))
        exportMarkdown.click()

        XCTAssertTrue(
            savePanel.waitForExistence(timeout: 10),
            "Export Markdown should present the system file exporter after reconstruction succeeds."
        )
        XCTAssertTrue(savePanel.buttons["Cancel"].waitForExistence(timeout: 5))
        savePanel.buttons["Cancel"].click()
        XCTAssertTrue(savePanel.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testLibraryMenuExposesBackupRestoreAndIntegrityCommands() throws {
        let app = launchApplication(seedSampleLibrary: true)
        XCTAssertTrue(app.descendants(matching: .any)["library-sidebar"].waitForExistence(timeout: 10))

        app.menuBars.menuBarItems["Library"].click()
        let backup = app.menuItems["Back Up Library…"]
        XCTAssertTrue(backup.waitForExistence(timeout: 5))
        XCTAssertTrue(app.menuItems["Restore Library…"].exists)
        XCTAssertTrue(app.menuItems["Import Legacy Library…"].exists)
        XCTAssertTrue(app.menuItems["Check Library Integrity"].exists)
        backup.click()

        let savePanel = app.sheets.firstMatch
        XCTAssertTrue(
            savePanel.waitForExistence(timeout: 10),
            "Back Up Library should present the system file exporter after snapshot validation."
        )
        let filenameField = savePanel.textFields["saveAsNameTextField"]
        XCTAssertTrue(filenameField.waitForExistence(timeout: 5))
        let filename = try XCTUnwrap(filenameField.value as? String)
        XCTAssertTrue(filename.hasSuffix(".ievelynlibrary"))
        XCTAssertFalse(
            filename.hasSuffix(".ievelynlibrary.ievelynlibrary"),
            "The system save panel should append the registered library extension exactly once."
        )
        XCTAssertTrue(savePanel.buttons["Cancel"].waitForExistence(timeout: 5))
        savePanel.buttons["Cancel"].click()
        XCTAssertTrue(savePanel.waitForNonExistence(timeout: 5))

        app.menuBars.menuBarItems["Library"].click()
        app.menuItems["Import Legacy Library…"].click()
        let importPanel = app.sheets.firstMatch
        XCTAssertTrue(
            importPanel.waitForExistence(timeout: 5),
            "Import Legacy Library should present a system file picker."
        )
        XCTAssertTrue(importPanel.buttons["Cancel"].waitForExistence(timeout: 5))
        importPanel.buttons["Cancel"].click()
        XCTAssertTrue(importPanel.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testImportedChapterStructurePersistsWithoutManualControls() throws {
        let app = launchApplication(
            seedSampleLibrary: false,
            bookContent: """
            # Chapter Workflow
            ### 作者：Test Author
            ## Opening

            Opening body.
            ## Ending

            Ending body.
            """
        )

        app.descendants(matching: .any)["library-add-book"].click()
        let title = app.textFields["book-editor-title"]
        let author = app.textFields["book-editor-author-0"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.click()
        title.typeText("Chapter Workflow")
        author.click()
        author.typeText("Test Author")
        app.descendants(matching: .any)["book-editor-save"].click()

        let actions = app.descendants(matching: .any)["Actions for Chapter Workflow"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        actions.click()
        XCTAssertFalse(app.menuItems["Book Info…"].exists)
        XCTAssertTrue(app.menuItems["Edit Book…"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(app.descendants(matching: .any)["chapter-management"].exists)

        let book = app.buttons["Chapter Workflow, by Test Author"]
        book.click()
        XCTAssertTrue(app.staticTexts["Opening body."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Show Sidebar"].waitForExistence(timeout: 5))
        app.typeKey("c", modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Table of Contents"].waitForExistence(timeout: 10))
        let tableOfContents = app.descendants(matching: .any)["reader-table-of-contents"]
        let opening = tableOfContents.descendants(matching: .staticText)["Opening"]
        XCTAssertTrue(opening.waitForExistence(timeout: 5))
        let ending = tableOfContents.descendants(matching: .staticText)["Ending"]
        XCTAssertTrue(ending.waitForExistence(timeout: 5))
        waitForChapter(opening, toAppearAbove: ending)
        ending.click()
        XCTAssertTrue(app.staticTexts["Ending body."].waitForExistence(timeout: 10))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["library-grid"].waitForExistence(timeout: 5))

        let currentlyReading = app.descendants(matching: .any)["sidebar-currentlyReading"]
        XCTAssertTrue(currentlyReading.waitForExistence(timeout: 5))
        currentlyReading.click()
        let currentlyReadingBook = app.buttons["Chapter Workflow, by Test Author"]
        XCTAssertTrue(
            currentlyReadingBook.waitForExistence(timeout: 5),
            "A saved location should place the book in Currently Reading."
        )
        currentlyReadingBook.click()
        XCTAssertTrue(
            app.staticTexts["Ending body."].waitForExistence(timeout: 10),
            "Reopening the reader should restore the last chapter."
        )
        XCTAssertTrue(app.buttons["Show Sidebar"].waitForExistence(timeout: 5))
        app.typeKey("c", modifierFlags: [])
        let reopenedTableOfContents = app.descendants(matching: .any)["reader-table-of-contents"]
        XCTAssertTrue(
            reopenedTableOfContents.descendants(matching: .staticText)["Opening"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            reopenedTableOfContents.descendants(matching: .staticText)["Ending"]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testReaderAddsNavigatesAndDeletesUnlabeledBookmark() throws {
        let app = launchApplication(
            seedSampleLibrary: false,
            bookContent: """
            # Bookmark Workflow
            ### Test Author
            ## Opening

            A location worth returning to.
            """
        )

        app.descendants(matching: .any)["library-add-book"].click()
        let title = app.textFields["book-editor-title"]
        let author = app.textFields["book-editor-author-0"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.click()
        title.typeText("Bookmark Workflow")
        author.click()
        author.typeText("Test Author")
        app.descendants(matching: .any)["book-editor-save"].click()

        let book = app.buttons["Bookmark Workflow, by Test Author"]
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.click()
        XCTAssertTrue(app.staticTexts["A location worth returning to."].waitForExistence(timeout: 10))

        let addBookmark = app.descendants(matching: .any)["reader-add-bookmark"]
        XCTAssertTrue(addBookmark.waitForExistence(timeout: 5))
        app.typeKey("b", modifierFlags: [])
        XCTAssertFalse(app.alerts["Add Bookmark"].exists)
        XCTAssertFalse(app.textFields["Label (Optional)"].exists)
        XCTAssertFalse(app.textFields["Note"].exists)

        app.typeKey("c", modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["reader-bookmarks"].waitForExistence(timeout: 5))
        let bookmarkLocation = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "reader-bookmark-location-")
        ).firstMatch
        XCTAssertTrue(bookmarkLocation.waitForExistence(timeout: 5))
        bookmarkLocation.click()
        XCTAssertTrue(app.staticTexts["A location worth returning to."].waitForExistence(timeout: 5))

        let deleteBookmark = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "reader-bookmark-delete-")
        ).firstMatch
        XCTAssertTrue(deleteBookmark.waitForExistence(timeout: 5))
        deleteBookmark.click()
        let confirmDelete = app.descendants(matching: .any)["reader-bookmark-confirm-delete"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["reader-bookmarks-empty"].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testReaderMovesBetweenChaptersAndReturnsToLibrary() throws {
        let app = launchApplication(
            seedSampleLibrary: false,
            bookContent: """
            # Reader Workflow
            ### Test Author
            ## Opening

            Opening chapter body
            ## Ending

            Ending chapter body
            """
        )

        app.descendants(matching: .any)["library-add-book"].click()
        let title = app.textFields["book-editor-title"]
        let author = app.textFields["book-editor-author-0"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.click()
        title.typeText("Reader Workflow")
        author.click()
        author.typeText("Test Author")
        app.descendants(matching: .any)["book-editor-save"].click()
        let book = app.buttons["Reader Workflow, by Test Author"]
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.click()

        XCTAssertTrue(
            app.staticTexts["Opening chapter body"].waitForExistence(timeout: 10),
            "Opening a book should render its first chapter in the reader window."
        )
        let showSidebar = app.buttons["Show Sidebar"]
        XCTAssertTrue(
            showSidebar.waitForExistence(timeout: 5),
            "A new reader window should start with its sidebar collapsed."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["reader-toggle-toc"].exists,
            "The reader should rely on NavigationSplitView's single native sidebar control."
        )

        let nextChapter = app.descendants(matching: .any)["reader-next-chapter"]
        XCTAssertTrue(nextChapter.waitForExistence(timeout: 5))
        XCTAssertTrue(nextChapter.isEnabled)
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Ending chapter body"].waitForExistence(timeout: 10))
        XCTAssertFalse(nextChapter.isEnabled)

        let previousChapter = app.descendants(matching: .any)["reader-previous-chapter"]
        XCTAssertTrue(previousChapter.isEnabled)
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Opening chapter body"].waitForExistence(timeout: 10))

        app.typeKey("c", modifierFlags: [])
        XCTAssertTrue(app.buttons["Hide Sidebar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Table of Contents"].waitForExistence(timeout: 5))

        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(
            app.staticTexts["Ending chapter body"].waitForExistence(timeout: 10),
            "Expanding the sidebar should focus its chapter list for Up/Down navigation."
        )
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Opening chapter body"].waitForExistence(timeout: 10))

        app.typeKey("c", modifierFlags: [])
        XCTAssertTrue(showSidebar.waitForExistence(timeout: 5))
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(
            app.staticTexts["Ending chapter body"].waitForExistence(timeout: 10),
            "Collapsing the sidebar should return focus to the reader panel."
        )

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["library-grid"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func waitForChapter(_ upperChapter: XCUIElement, toAppearAbove lowerChapter: XCUIElement) {
        let reordered = expectation(
            for: NSPredicate { _, _ in
                upperChapter.exists && lowerChapter.exists && upperChapter.frame.minY < lowerChapter.frame.minY
            },
            evaluatedWith: upperChapter
        )
        wait(for: [reordered], timeout: 5)
    }

    @MainActor
    private func launchApplication(
        seedSampleLibrary: Bool,
        bookContent: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState",
            "YES",
            "--ui-testing"
        ]
        if seedSampleLibrary {
            app.launchArguments.append("--seed-sample-library")
        }
        if let bookContent {
            app.launchEnvironment["IEVELYN_UI_TEST_CONTENT_BASE64"] =
                Data(bookContent.utf8).base64EncodedString()
        }
        app.launch()
        return app
    }
}
