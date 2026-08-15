# iEvelyn Sequential Implementation Plan

Last updated: 2026-08-14

## Purpose

This is the authoritative step-by-step implementation plan for iEvelyn. Work proceeds in order. Each step must leave the application runnable and testable. After completing a step, provide its manual checkpoint and stop so the user can run and test it before authorizing the next step.

Read `PROJECT_CONTEXT.md` for product and architecture decisions and `AGENTS.md` for working rules.

## Current status

- Current milestone: Step 4 — Book management.
- Implementation status: not started; awaiting authorization.
- Xcode project: created with app, unit-test, and UI-test targets.
- Git repository: initialized on `main` and tracking `origin/main`.
- All step status changes require user confirmation after the manual checkpoint.

## Working protocol

For every step:

1. Re-read `AGENTS.md`, this plan, and the relevant sections of `PROJECT_CONTEXT.md`.
2. Inspect the working tree and toolchain before editing.
3. Implement only the step explicitly authorized by the user.
4. Keep the app building and preserve all previously accepted behavior.
5. Add or update focused automated tests for behavior introduced by the step.
6. Run the relevant build and test commands.
7. Report the outcome, changed files, automated checks, limitations, and an exact manual test checklist.
8. Stop. Do not begin the next step until the user confirms the manual checkpoint.
9. After confirmation, mark the completed step in the progress table and identify the next step.

Do not create commits, branches, tags, releases, or pull requests unless the user explicitly asks.

## Definition of done for a step

A step is implementation-complete when:

- Its listed deliverables are present.
- The app builds with the supported Xcode toolchain.
- Relevant automated tests pass.
- Existing accepted workflows still work.
- Errors are surfaced to the user instead of being silently discarded.
- Any meaningful deviation from this plan is documented and explained.
- The agent has supplied a concise manual checkpoint.

A step is accepted only after the user reports that its manual checkpoint passes or explicitly accepts known limitations.

## Dependency schedule

Add dependencies only in the step that first needs them:

| Step | Dependency | Purpose |
| --- | --- | --- |
| 3 | GRDB | SQLite schema, migrations, repositories, observation, test databases |
| 8 | `swift-markdown` | Parse canonical Markdown into a semantic syntax tree |
| 12 | ZIPFoundation | Build EPUB ZIP containers with explicit entry control |

Use Swift Package Manager. Pin versions through the Xcode project or package resolution file and record material compatibility decisions. Do not add broad UI, architecture, or utility frameworks without a demonstrated need.

## Step 0 — New-Mac prerequisites and workspace baseline

### Goal

Establish a reproducible development environment before generating source files.

### Deliverables

- Copy or clone the complete `iEvelyn` folder to the new Mac.
- Install a full, current Xcode release that supports the chosen macOS 26 SDK and Swift 6 mode.
- Launch Xcode once, accept the license, and allow required components to install.
- Select the intended Xcode developer directory if multiple installations exist.
- Confirm sufficient disk space for Xcode, simulators/components actually needed, Derived Data, and archives.
- Confirm the three documentation files are present and readable.
- Decide whether to initialize this folder as a Git repository. Do not create a commit unless explicitly requested.

### Automated checks

Run and record:

```sh
xcodebuild -version
xcrun swift --version
xcode-select -p
git status --short
```

The final command may report that the folder is not a repository until Git initialization is authorized.

### Manual checkpoint

- Open Xcode successfully.
- Confirm macOS project templates are available.
- Confirm the `iEvelyn` folder is the primary local-project folder in ChatGPT/Codex.
- Ask the coding agent to summarize the current milestone from these documents; verify that it identifies Step 1 as next without starting it.

## Step 1 — Bootstrap the native macOS project

### Goal

Create the smallest correct SwiftUI macOS application and test targets.

### Deliverables

- Create an Xcode macOS App project named `iEvelyn` in this folder.
- Use the SwiftUI app lifecycle and current Swift 6 language mode.
- Set the deployment target to macOS 26.
- Confirm the product name and choose a bundle identifier with the user if none has been supplied.
- Add a Swift Testing unit-test target and an XCTest UI-test target.
- Enable App Sandbox with only the file access needed for user-selected imports and exports.
- Establish this source layout, adapting Xcode groups to filesystem-backed folders:

```text
iEvelyn/
├── App/
├── Domain/
├── Persistence/
├── Features/
│   ├── Library/
│   ├── BookDetails/
│   ├── Editor/
│   └── Reader/
├── Services/
│   ├── Assets/
│   ├── Rendering/
│   ├── EPUB/
│   └── Import/
├── Shared/
├── Resources/
├── iEvelynTests/
└── iEvelynUITests/
```

- Provide a minimal native window, app menu, About placeholder, and testable root view.
- Record the exact build scheme and working command-line build/test commands in `AGENTS.md`.

### Automated checks

- Debug build succeeds through Xcode and `xcodebuild`.
- Unit tests pass.
- UI smoke test launches the application and verifies the root view exists.

### Manual checkpoint

- Run with Command-R.
- Confirm a native app window opens without a browser or server.
- Check app menus and About placeholder.
- Switch macOS between light and dark appearances.
- Run the full test suite with Command-U.

## Step 2 — Build the visual library shell with sample data

### Goal

Validate the primary macOS information architecture and visual direction before persistence is introduced.

### Deliverables

- Build a `NavigationSplitView`-based main window.
- Add sidebar destinations: All Books, Currently Reading, Recently Added, Favorites, Authors, Tags, and Trash.
- Add cover-grid and list presentations using in-memory sample books.
- Add search, sort controls, selection, a book-detail placeholder, and a polished empty-library state.
- Add a toolbar and initial keyboard commands.
- Define a small set of reusable design tokens for spacing, cover proportions, typography, and selection states.
- Support a second window without sharing transient selection incorrectly.
- Keep all sample data isolated so it can be replaced cleanly in Step 3.

### Automated checks

- Unit tests cover sorting, filtering, and sample-model behavior.
- UI smoke tests cover sidebar navigation, grid/list switching, search, and empty state.

### Manual checkpoint

- Resize from compact to wide window sizes.
- Collapse and restore the sidebar.
- Switch grid/list modes, sort orders, and destinations.
- Search for a sample book and clear the search.
- Open a second window and verify independent selection.
- Check light/dark appearance, keyboard focus, and basic VoiceOver labels.

## Step 3 — Add SQLite persistence with GRDB

### Goal

Replace sample data with a durable, testable library database.

### Deliverables

- Add GRDB through Swift Package Manager.
- Finalize the initial normalized schema for books, authors, book-authors, chapters, assets, tags, book-tags, reading progress, and bookmarks.
- Use UUID domain identities, explicit ordering, timestamps, foreign keys, indexes, and appropriate uniqueness constraints.
- Add ordered schema migrations from an empty database.
- Enable foreign-key enforcement and configure WAL after verifying the chosen GRDB setup.
- Add repository/data-access boundaries and dependency injection for live and test databases.
- Store the production database under the sandboxed Application Support directory.
- Use temporary or in-memory databases for tests.
- Add GRDB observations needed for responsive updates across windows.
- Add Debug-only sample-library seeding and reset actions that cannot be invoked in release builds.

### Automated checks

- Migration tests build a database from version zero.
- CRUD, constraint, cascade/restrict, transaction rollback, ordering, and observation tests pass.
- Tests prove production library paths are never used by the test suite.

### Manual checkpoint

- Seed sample data, quit, and relaunch; confirm persistence.
- Open two windows and verify a change appears in both.
- Use the Debug reset action and confirm the app returns to a valid empty state.
- Relaunch again and confirm database integrity.

## Step 4 — Implement book management

### Goal

Make the library useful for real book records before adding files or chapters.

### Deliverables

- Create, view, edit, and validate book metadata.
- Cover title, subtitle, ordered authors, summary, language, and relevant publication fields.
- Support favorite/unfavorite.
- Support library sorting and filtering against real persisted data.
- Implement soft deletion to Trash, restore, and explicit permanent deletion.
- Maintain created, updated, and recently-opened timestamps consistently.
- Supply clear validation, empty, and database-error states.

### Automated checks

- Repository and feature tests cover create/update, author relationships, validation, favorite, filters, soft delete, restore, and permanent delete.
- UI tests cover the primary add/edit/trash workflow.

### Manual checkpoint

- Add several books with single and multiple authors.
- Edit metadata and verify sorting/filtering.
- Favorite a book.
- Move a book to Trash, restore it, then permanently delete a disposable book.
- Quit/relaunch and verify all states persist.

## Step 5 — Add cover and asset storage

### Goal

Safely import and display cover art while establishing the reusable asset subsystem.

### Deliverables

- Create the Application Support library layout described in `PROJECT_CONTEXT.md`.
- Add a SwiftUI file importer for supported cover formats such as JPEG, PNG, and HEIC.
- Validate media type and basic readability before import.
- Copy imports atomically into UUID-addressed per-book asset storage.
- Record relative paths, checksums, sizes/dimensions, and purpose in SQLite.
- Generate and cache thumbnails without changing the authoritative asset.
- Support replace and remove cover operations.
- Clean up orphaned files after committed database changes, with failure reporting and repairability.
- Define the safe `book-asset://` resolution boundary used later by the renderer.

### Automated checks

- Tests cover import, replacement, checksum behavior, unsupported files, atomic failure, orphan detection, and permanent cleanup in temporary directories.

### Manual checkpoint

- Import JPEG, PNG, and HEIC covers.
- Verify grid/list/detail display and thumbnail quality.
- Replace and remove a cover.
- Delete the original source image and confirm the app's copy still works.
- Relaunch and verify persistence.
- Permanently delete a disposable book and confirm its owned assets are cleaned up.

## Step 6 — Implement chapter management

### Goal

Provide a robust, ordered chapter structure for each book.

### Deliverables

- Add, rename, duplicate, and delete chapters.
- Provide recoverable undo for chapter deletion within the active editing session.
- Reorder chapters with drag and drop inside a transaction.
- Maintain stable chapter UUIDs independent of order.
- Add chapter selection, empty states, chapter count, and word-count summaries.
- Define consistent behavior for an empty book and a one-chapter book.

### Automated checks

- Tests cover ordering, duplicate titles, stable identities, transactional reorder, delete/undo, and aggregate counts.
- UI tests cover add, select, reorder, and delete.

### Manual checkpoint

- Create chapters, use duplicate names, rename them, and reorder them.
- Delete and undo a chapter deletion.
- Quit/relaunch and confirm order and selection behavior.
- Verify empty-book guidance and counts.

## Step 7 — Build the Markdown chapter editor

### Goal

Make Markdown the reliable canonical authoring source.

### Deliverables

- Add a native Markdown source editor with monospaced/editing-appropriate typography.
- Implement debounced autosave and a visible saved/saving/error state.
- Integrate `UndoManager`, find/replace, selection, and standard edit commands.
- Show word and character counts.
- Import UTF-8 Markdown and plain-text chapter files through a user-selected file importer.
- Prevent stale asynchronous saves from overwriting newer edits or another selected chapter.
- Add a split-preview layout with a clear preview placeholder; rendering arrives in Step 8.
- Handle very large chapters without unnecessary full-view recomputation.

### Automated checks

- Tests cover autosave ordering, switching chapters during a save, error recovery, imports, undoable edits, and counts.

### Manual checkpoint

- Edit a long chapter rapidly and switch chapters during autosave.
- Exercise undo/redo and find/replace.
- Import Markdown and plain text, including Unicode.
- Quit during normal use, relaunch, and confirm the latest saved text.
- Simulate or inspect a save failure and verify it is visible and recoverable.

## Step 8 — Create the Markdown rendering engine

### Goal

Produce deterministic, safe reader HTML and EPUB XHTML from the same canonical source.

### Deliverables

- Add `swift-markdown` through Swift Package Manager.
- Document the supported Markdown dialect, including decisions for tables, task lists, footnotes, and raw HTML.
- Parse Markdown into a semantic representation.
- Implement separate controlled output modes for reader HTML and strict EPUB XHTML.
- Generate deterministic stable block IDs to support reading anchors.
- Resolve known assets only through the application asset resolver.
- Sanitize, escape, reject, or explicitly support raw HTML according to the documented policy.
- Add accessible, themeable CSS for prose, code, quotes, lists, tables, and images.
- Cache derived output by source hash plus renderer version; make cache invalidation deterministic.
- Replace the Step 7 preview placeholder with live rendered preview.

### Automated checks

- Golden/fixture tests cover headings, paragraphs, emphasis, links, lists, quotes, code, tables if supported, images, Unicode, malformed input, raw HTML, and stable IDs.
- Tests confirm reader HTML and EPUB XHTML meet their different structural rules.
- Cache invalidation tests cover source and renderer-version changes.

### Manual checkpoint

- Open a comprehensive Markdown chapter and compare source with preview.
- Edit while preview is open and verify timely, stable updates.
- Check light/dark styling, long lines, code, links, images, and Unicode.
- Verify unsupported or unsafe markup fails safely and visibly.

## Step 9 — Build the reading experience

### Goal

Deliver the core Apple Books-like reading workflow.

### Deliverables

- Embed the reader with modern SwiftUI/WebKit APIs for macOS 26.
- Add a dedicated reader window and correct multi-window state ownership.
- Add table of contents, previous/next chapter, and chapter jump navigation.
- Support continuous chapter reading and evaluate an optional CSS column/paginated mode without compromising accessibility.
- Add font family/size, line height, content width, and theme controls.
- Add Find in Book, full-screen mode, keyboard shortcuts, and trackpad-friendly navigation.
- Open external links safely outside the trusted book content context.
- Use a quiet toolbar that can recede while reading and return predictably.

### Automated checks

- Tests cover reader document generation, navigation state, settings persistence, safe URL handling, and chapter boundary behavior.
- UI tests cover opening/closing a reader and moving between chapters.

### Manual checkpoint

- Read a multi-chapter book from beginning to end.
- Use table of contents, previous/next, search, keyboard shortcuts, and full screen.
- Change typography and themes and verify persistence.
- Test long chapters, images, external links, window resizing, and VoiceOver reading order.

## Step 10 — Add progress, bookmarks, and notes

### Goal

Restore reading sessions reliably even when content changes.

### Deliverables

- Track last-opened book, chapter, read time, and overall progress for Currently Reading.
- Persist the layered semantic anchor described in `PROJECT_CONTEXT.md`.
- Automatically restore the last reading location.
- Add manual bookmarks with labels and optional notes if included in the accepted scope.
- Add a bookmark list with direct navigation and delete/edit actions.
- Implement quote/context reattachment and graceful fallback after source edits.
- Define behavior when a bookmarked chapter or block is deleted.

### Automated checks

- Tests cover progress calculations, anchor serialization, exact restore, quote reattachment, content-edit fallback, deleted content, and bookmark CRUD.

### Manual checkpoint

- Stop mid-chapter, quit, relaunch, and verify restoration.
- Add several bookmarks and navigate from the list.
- Edit content before a saved location and verify reattachment.
- Remove the exact bookmarked block and verify graceful fallback.
- Confirm Currently Reading order and progress update correctly.

## Step 11 — Add full-text search and organization

### Goal

Make a substantial library fast to find and organize.

### Deliverables

- Add SQLite FTS5 indexing for book title/subtitle, authors, chapter titles/content, tags, and bookmark notes if present.
- Keep the index synchronized transactionally or through tested rebuild logic.
- Add result snippets, scoped searches, and direct navigation to matching chapters/locations.
- Add author and tag management with counts and filters.
- Ensure deleted books are excluded from ordinary results.
- Add explicit index rebuild/repair behavior for diagnostics.

### Automated checks

- Tests cover metadata/content matches, Unicode, snippets, updates/deletes, scope filters, index rebuild, and direct navigation.
- Include a representative performance test dataset without relying on the user's library.

### Manual checkpoint

- Search title, author, tag, chapter title, and chapter body terms.
- Test Unicode and punctuation-heavy queries.
- Jump from a result to the matching chapter/location.
- Edit and delete content and confirm results update.
- Verify trashed books remain excluded except in a deliberately scoped Trash search.

## Step 12 — Implement EPUB 3 export

### Goal

Generate interoperable EPUB files from iEvelyn books.

### Deliverables

- Add ZIPFoundation through Swift Package Manager.
- Generate EPUB 3 metadata, stable identifiers, cover, XHTML chapters, CSS, navigation document, OPF manifest, and spine.
- Include only referenced, supported assets with correct media types and relative links.
- Write `mimetype` first and uncompressed and package remaining entries correctly.
- Export with SwiftUI `fileExporter` to a user-selected destination.
- Report missing metadata/assets and rendering errors before producing a misleading file.
- Allow deterministic re-export after content edits.
- Add a developer-facing validation workflow using a recognized EPUB validator when available.

### Automated checks

- Inspect archive entry order/compression, required files, XML/XHTML well-formedness, manifest/spine consistency, links, IDs, and asset coverage.
- Test one-chapter, multi-chapter, image-containing, Unicode, and invalid-source books.

### Manual checkpoint

- Export one-chapter and multi-chapter books, including a book with images.
- Open each in Apple Books and inspect cover, metadata, table of contents, formatting, images, and navigation.
- Edit a chapter, re-export, and confirm the change.
- Run the documented EPUB validation and review all warnings/errors.

## Step 13 — Add backup, restore, and interchange

### Goal

Make the local library portable and recoverable before legacy migration is attempted.

### Deliverables

- Define and document a versioned iEvelyn library bundle.
- Include a consistent data snapshot, assets, manifest, counts, checksums, timestamp, format version, and app version.
- Create backups atomically to a user-selected destination.
- Restore by validating and constructing a temporary library before an atomic swap.
- Preserve the current library unchanged after a failed validation or restore.
- Add a human-readable integrity-check and repair report.
- Add optional per-book Markdown export for simple source portability.

### Automated checks

- Round-trip tests compare records, relationships, Markdown, and asset checksums.
- Failure tests cover missing files, corrupt checksums, unsupported versions, interrupted restore, and rollback.

### Manual checkpoint

- Create a backup, mutate the working library, restore, and compare results.
- Inspect the bundle manifest and asset contents.
- Corrupt a disposable copy and verify restore refuses it without damaging the current library.
- Export Markdown and inspect the result in another editor.

## Step 14 — Build the separate legacy data exporter

### Goal

Extract useful Evelyn.NET data safely into a neutral import bundle without modifying PostgreSQL.

### Deliverables

- Create `/Users/cysun/git/EvelynMigration` as a separate .NET console project.
- Use a dedicated read-only PostgreSQL connection and fail closed if required configuration is missing.
- Export book metadata, ordered canonical chapter Markdown, cover images, and referenced content assets.
- Optionally export legacy bookmark/progress data only after assessing its reliability.
- Exclude users, password hashes, authorization data, web configuration, generated HTML, thumbnails that can be regenerated, and generated EPUB output unless a reviewed exception is necessary.
- Write a documented, versioned neutral bundle consumable by iEvelyn.
- Produce source/export counts, checksums, warnings, skipped items, and legacy-ID mapping reports.
- Support dry-run and deterministic repeated export.
- Never update, delete, lock unnecessarily, or migrate the source database.

### Automated checks

- Unit/integration tests use fixtures or a disposable PostgreSQL instance, never the live legacy database.
- Tests cover nulls, missing blobs, invalid encodings, duplicate/odd ordering, missing Markdown, checksums, determinism, and report counts.

### Manual checkpoint

- Run dry-run and compare source counts with the report.
- Export a representative subset if supported, then the full library.
- Inspect several metadata records, Markdown chapters, covers, assets, warnings, and skipped items.
- Run export again and verify deterministic results where expected.
- Confirm independently that the source database remains unchanged.

## Step 15 — Import the legacy bundle into iEvelyn

### Goal

Migrate the verified neutral bundle into the native library with validation and rollback.

### Deliverables

- Add an import wizard that validates the manifest, version, counts, checksums, media, and references before writing.
- Provide a dry-run summary of additions, skips, warnings, and conflicts.
- Map legacy IDs to new UUIDs without making legacy identifiers domain keys.
- Build the imported SQLite database in a temporary location and copy assets atomically.
- Rebuild derived reader output, thumbnails, and search indexes locally.
- Detect likely duplicate books and require an explicit strategy rather than silently merging.
- Commit the imported library only after full validation.
- Produce a permanent reconciliation report and retain rollback safety.

### Automated checks

- Fixture imports verify counts, ordering, authors, Markdown, assets, hashes, duplicate handling, and re-rendering.
- Failure tests cover corrupt bundles, missing assets, unsupported versions, interrupted import, and rollback.
- Re-import behavior is defined and tested.

### Manual checkpoint

- Review the dry-run summary before import.
- Compare final counts and warnings with the exporter report.
- Inspect representative books, multi-author metadata, chapter order, Unicode, covers, and images.
- Search imported content and restore a reading location if migrated.
- Export representative imported books to EPUB and open them in Apple Books.
- Repeat import against a disposable library and test corrupt-bundle rollback.

## Step 16 — Polish and release readiness

### Goal

Turn the functionally complete application into a dependable signed macOS release candidate.

### Deliverables

- Complete VoiceOver labels, keyboard navigation, menus, shortcuts, focus behavior, and accessibility audits.
- Add window and navigation state restoration.
- Finish empty, loading, validation, database-corruption, missing-asset, and recovery UI.
- Profile startup, scrolling, search, rendering, and large-library behavior.
- Audit structured concurrency, actor isolation, cancellation, and main-thread I/O.
- Audit privacy-sensitive logs and entitlements.
- Add the final app icon, About content, version/build display, and user documentation.
- Configure signing, hardened runtime, archive, and notarization for the user's intended distribution method.
- Expand UI smoke tests around the highest-value end-to-end workflows.
- Document backup expectations, supported Markdown, migration limitations, and known issues.

### Automated checks

- Clean Debug and Release builds pass.
- Unit, integration, rendering, EPUB, migration-fixture, and UI smoke tests pass.
- Static diagnostics and concurrency warnings are resolved or explicitly documented.
- A signed archive is produced and validated according to the chosen distribution path.

### Manual checkpoint

- Exercise a clean install and first launch.
- Create a book, add a cover and chapters, edit/read/search/bookmark it, export EPUB, back up, and restore.
- Test a large representative library.
- Test keyboard-only and VoiceOver workflows.
- Test light/dark appearance, multiple windows, full screen, restart, and recovery messaging.
- Install and run the signed release build on a second compatible Mac if available.

## Progress table

Use only these statuses: `Not started`, `In progress`, `Awaiting manual test`, `Accepted`, `Blocked`.

Do not mark a step `Accepted` until the user confirms its manual checkpoint. At most one step may be `In progress` or `Awaiting manual test`.

| Step | Milestone | Status | Acceptance notes |
| ---: | --- | --- | --- |
| 0 | New-Mac prerequisites and workspace baseline | Accepted | Xcode 26.6 selected from `/Volumes/galfrey`; Swift 6.3.3; external Derived Data configured; Git workspace confirmed. |
| 1 | Bootstrap native macOS project | Accepted | Manual Command-R, menus/About, light/dark appearance, and Command-U checkpoint passed on 2026-08-14. |
| 2 | Visual library shell with sample data | Accepted | Debug build, seven unit tests, and three UI smoke tests passed; visual, navigation, search, appearance, and multi-window checkpoint accepted on 2026-08-14. |
| 3 | SQLite persistence with GRDB | Accepted | GRDB 7.11.1 resolved; Debug and Release builds, 18 unit/integration tests, and three UI smoke tests passed; persistence, multi-window observation, and Debug reset checkpoint accepted on 2026-08-14. |
| 4 | Book management | Not started | |
| 5 | Cover and asset storage | Not started | |
| 6 | Chapter management | Not started | |
| 7 | Markdown chapter editor | Not started | |
| 8 | Markdown rendering engine | Not started | |
| 9 | Reading experience | Not started | |
| 10 | Progress, bookmarks, and notes | Not started | |
| 11 | Full-text search and organization | Not started | |
| 12 | EPUB 3 export | Not started | |
| 13 | Backup, restore, and interchange | Not started | |
| 14 | Separate legacy data exporter | Not started | |
| 15 | Native legacy-bundle importer | Not started | |
| 16 | Polish and release readiness | Not started | |

## Plan maintenance

- Keep completed step descriptions intact unless correcting an error; they are part of the project's decision history.
- Record acceptance notes briefly in the progress table after user confirmation.
- Add newly discovered work to the most appropriate future step instead of silently expanding the active step.
- If a prerequisite changes the order, explain the dependency and receive user approval before resequencing.
- Material architecture changes belong in `PROJECT_CONTEXT.md` as well as this plan.
