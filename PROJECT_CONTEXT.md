# iEvelyn Project Context

Last updated: 2026-08-15

## Purpose of this document

This document preserves the product vision, architecture decisions, data strategy, and constraints for iEvelyn. It is the durable context for future work. Implementation sequencing and progress live in `IMPLEMENTATION_PLAN.md`; instructions for coding agents live in `AGENTS.md`.

## Product vision

iEvelyn is a completely new, native macOS application for managing, authoring, and reading a personal ebook library. The desired experience is closer to Apple Books than to an administrative database application, while also supporting author-focused capabilities such as adding and editing chapters and exporting EPUB files.

The existing Evelyn.NET application is a source of legacy book data only. Its web UI, ASP.NET controllers, authentication model, browser-based reader, database schema, and implementation patterns are not design constraints for iEvelyn.

## Product goals

- Deliver a polished, modern, macOS-only application using native conventions.
- Make the library pleasant to browse in grid and list forms.
- Provide a focused reading experience with themes, typography controls, navigation, search, progress, and bookmarks.
- Let the user create books, manage metadata and covers, add and reorder chapters, and edit chapter source in Markdown.
- Generate standards-oriented EPUB 3 files from the same canonical content used by the app.
- Store the local library in an explicit, inspectable SQLite database with externally stored assets.
- Migrate useful book data from Evelyn.NET without coupling the new application to PostgreSQL or the old schema at runtime.
- Protect the library with atomic writes, versioned migrations, backup and restore, validation, and recoverable deletion.

## Non-goals for the initial product

- Reproducing or visually mimicking the Evelyn.NET UI.
- Porting ASP.NET Core code, web authentication, users, password hashes, cookies, or server configuration.
- Running a local web server.
- Connecting the shipping macOS application directly to the legacy PostgreSQL database.
- Cross-platform support.
- iPhone or iPad versions.
- Cloud sync, collaboration, accounts, or a hosted service.
- DRM creation or removal.
- A full WYSIWYG publishing system in the first implementation. Markdown source editing is the initial authoring model.

## Target user experience

### Library

The main window uses a native sidebar and a full browsing area rather than a persistent metadata column. Expected library sections include All Books, Currently Reading, Recently Added, Favorites, Authors, Tags, and Trash. Books can be displayed as cover grids or compact lists, searched, filtered, and sorted. The cover grid uses artwork for visual browsing; the compact list omits tiny cover thumbnails and prioritizes title, author, library date, and progress. Activating a book opens the reader; information and management actions belong to that book's compact More menu and on-demand sheets rather than a selection-dependent toolbar. The interface must have thoughtful empty, loading, and error states and work well in light and dark appearances.

### Book management and authoring

A book detail experience exposes metadata, cover art, chapter structure, and relevant actions. Users can create and edit books, add or import chapters, reorder them, and edit canonical Markdown with autosave, undo, find/replace, and preview. Destructive actions should be recoverable wherever practical.

### Reading

Reading should occur in a dedicated, distraction-reduced window with a table of contents, previous/next chapter navigation, configurable typography, light/dark/sepia-style themes, full-screen support, Find in Book, progress restoration, and semantic bookmarks. Keyboard and accessibility support are first-class requirements.

### EPUB generation

EPUB is an export format generated on demand from canonical book content and assets. Export should produce EPUB 3 metadata, XHTML chapters, navigation, styles, cover art, and a correct package/spine. Generated EPUB files are outputs, not the authoritative source of a book.

## Fixed technical direction

These choices are the current baseline. Changing one requires a documented reason and user approval when it materially changes the plan.

### Platform and UI

- Product display name: iEvelyn.
- Bundle identifier: `org.cysun.iEvelyn`.
- Minimum platform: macOS 26.
- Language: the current Swift 6 language mode supported by the selected Xcode release.
- App lifecycle and UI: SwiftUI.
- AppKit may be used only when SwiftUI lacks a required macOS capability; isolate and document such bridges.
- Reader: WebKit embedded in SwiftUI, using the modern WebKit SwiftUI APIs available on the minimum platform.

### Persistence

- Database: SQLite.
- Database library: GRDB.
- Schema evolution: explicit, ordered, versioned database migrations.
- Database access: repositories or focused data-access services; views must not contain SQL.
- Live UI updates: GRDB observations where they improve responsiveness and multi-window consistency.
- Enable foreign-key enforcement and use write-ahead logging when supported by the final configuration.

GRDB 7.11.1 is integrated through Swift Package Manager. The project requires a compatible 7.x release starting at 7.11.1, while `Package.resolved` records the exact reviewed build. GRDB is MIT-licensed. Dependency updates should continue to be explicit and should rerun migrations, persistence tests, Debug/Release builds, and the UI smoke suite.

SQLite is preferred over an opaque persistence layer because the library format should remain inspectable, migration behavior should be explicit, and full-text search and transactions are important features.

### Content model

- Markdown is the canonical editable representation of a chapter.
- Reader HTML and EPUB XHTML are derived representations generated from Markdown.
- Derived markup may be cached using a source hash and renderer-version key, but it must be safe to discard and rebuild.
- The accepted Markdown dialect and raw-HTML policy must be documented and covered by rendering tests.
- Use `swift-markdown` as the parser and build controlled renderers for reader HTML and EPUB XHTML.

Keeping both Markdown and HTML as independently editable database fields is explicitly avoided because the two representations can drift.

### Assets

- Store asset metadata and ownership in SQLite.
- Store cover images and chapter assets as files under the application's sandboxed Application Support directory.
- Address assets by stable UUIDs, never by user-supplied file names alone.
- Copy imported files atomically, validate supported media types, and generate disposable thumbnails or render caches as needed.
- Rendering should use an application-specific asset URL mechanism such as `book-asset://` instead of exposing arbitrary local paths.

### EPUB

- Use ZIPFoundation for packaging unless Step 12 identifies a concrete reason to change.
- The `mimetype` entry must be first and uncompressed.
- Export must use generated EPUB-safe XHTML rather than reader HTML copied verbatim.
- Export should include structural tests and validation guidance; Apple Books is a required manual interoperability check.

### Legacy migration

- Migration is a one-time, explicit workflow, not runtime compatibility code.
- Build a separate .NET console exporter in `/Users/cysun/git/EvelynMigration` during Step 14.
- The exporter reads the old PostgreSQL database in read-only mode and writes a neutral, documented bundle.
- The native iEvelyn importer validates that bundle and imports into a temporary library before an atomic commit.
- Legacy identifiers may appear in migration reports or mappings but do not become the new domain identity scheme.

## Initial persisted domain model

Step 3 finalized the initial normalized schema with these concepts:

| Concept | Responsibility |
| --- | --- |
| `Book` | Title, subtitle, summary, favorite/trash state, library timestamps, cover reference |
| `Author` | Reusable normalized author identity and display name |
| `BookAuthor` | Ordered many-to-many relationship between books and authors |
| `Chapter` | Stable UUID, book ownership, title, canonical Markdown, order, timestamps, render revision/hash |
| `Asset` | Stable UUID, book ownership, media type, relative storage path, checksum, dimensions or size, purpose |
| `Tag` | User-managed organization label |
| `BookTag` | Many-to-many relationship between books and tags |
| `ReadingProgress` | Last location and read timestamp for a book |
| `Bookmark` | Named or unnamed semantic reading anchor, optional note, timestamps |

Use UUIDs for new domain identities. Store ordering explicitly. Use foreign keys and transactions for multi-record changes such as chapter reordering or permanent book deletion.

Initial schema decisions:

- Store UUIDs as lowercase 36-character text so database inspection and migration reports remain readable.
- Store dates as integer milliseconds since the Unix epoch and decode them through one shared GRDB record policy.
- The v2 migration removes language, publisher, and publication-date columns. iEvelyn's online self-published serials retain Added and Updated as library metadata instead of publication metadata.
- Enforce nonempty titles/names, normalized unique author and tag names, unique ordered author/chapter positions, progress ranges, nonnegative asset sizes, and one cover-purpose asset per book.
- Model a book's cover through its unique owned `Asset` whose purpose is `cover`, avoiding a circular book/asset foreign key.
- Cascade permanent book deletion through owned joins, chapters, assets, progress, and bookmarks. Restrict deletion of authors or tags while linked to a book.
- Set chapter references on assets, reading progress, and bookmarks to null when a chapter is deleted, preserving book-level ownership and anchor fallback. Triggers reject cross-book chapter references.
- Keep `trashedAt` as the book soft-deletion boundary; Step 4 supplies the user workflow.

## Reading-location strategy

A bookmark or saved reading position must not depend only on a raw paragraph number or DOM offset, because editing a chapter would make it fragile. Store a layered anchor:

- Book UUID and chapter UUID.
- Stable generated block identifier when available.
- A short normalized text quote and nearby context for reattachment.
- A fractional or character-based fallback position within the chapter.
- A final chapter-level fallback when the exact content no longer exists.

The renderer must produce deterministic block identifiers from semantic source positions or stable content metadata. Reattachment behavior should be tested after chapter edits.

## Local library layout

Resolve all paths through `FileManager`; do not hardcode a user's home path. A conceptual layout under the app's sandboxed Application Support location is:

```text
iEvelyn/
├── Library.sqlite
├── Library.sqlite-shm              # SQLite-managed when present
├── Library.sqlite-wal              # SQLite-managed when present
├── Assets/
│   └── Books/
│       └── <book-uuid>/
│           └── <asset-uuid>.<ext>
└── Cache/
    ├── Covers/
    └── Reader/
```

The cache is disposable. Assets are not disposable and must be included in backup, restore, integrity checks, and permanent-deletion transactions.

## Portable interchange and backup bundle

Step 13 should define a versioned bundle suitable for backup/restore and internal interchange. At minimum it should contain:

- A manifest with format version, creation timestamp, app version, and counts.
- A consistent SQLite snapshot or neutral data representation.
- All referenced non-cache assets.
- Checksums for integrity validation.
- Enough metadata to reject unsupported future versions safely.

Restore must validate into a temporary location and replace the active library only after all checks pass. A failed restore must leave the existing library untouched.

## Legacy Evelyn.NET facts relevant to migration

The old application is an ASP.NET Core application using Entity Framework Core and PostgreSQL. Its relevant tables include users, files, books, chapters, and bookmarks. File content is stored as database byte arrays. Chapter content is stored in both Markdown and generated HTML, and Markdig has been used to derive HTML. Covers, thumbnails, and generated EPUBs may also be stored as file blobs. The existing reader is browser-based and bookmark locations have relied on paragraph-oriented indexing.

Migration rules:

- Prefer legacy Markdown as chapter source.
- Treat legacy HTML as derived data and do not normally import it.
- If Markdown is missing or demonstrably unusable, any HTML-to-Markdown recovery must be an explicit, reported exception.
- Import useful book metadata, ordered chapters, covers, and referenced content assets.
- Decide separately whether legacy bookmarks/progress are reliable enough to migrate; do not silently pretend paragraph indices are semantic anchors.
- Exclude users, password hashes, cookies, authorization data, server configuration, and generated legacy HTML/EPUB output.
- Produce counts, checksums, warnings, and a skipped-item report so the user can reconcile the migration.
- Keep the source database read-only and make repeated exports deterministic.

## Quality, privacy, and safety requirements

- The core app is local-first and should not require an account or network connection.
- Do not add analytics, telemetry, crash uploads, or cloud features without explicit user approval.
- Never log book content, credentials, secrets, or full local paths in production logs.
- Use App Sandbox and the minimum entitlements needed for user-selected import/export.
- Perform database and file work away from the main actor while keeping UI state changes correctly isolated.
- Use atomic file replacement and database transactions for operations spanning records and assets.
- Validate imported bundles and media. Render untrusted raw HTML conservatively.
- Soft-delete books before permanent removal. Permanent deletion must be explicit and covered by tests.
- Tests must use temporary directories and disposable databases, never the user's real library.
- Accessibility, keyboard navigation, state restoration, and dark appearance are acceptance criteria, not post-release extras.

## Current project state

As of 2026-08-15:

- `/Users/cysun/git/iEvelyn` is a Git repository on `main`, tracking `origin/main`; Step 1 was accepted on 2026-08-14.
- The native SwiftUI project, app target, Swift Testing target, and XCTest UI-test target exist, and the Step 1 manual checkpoint passed.
- Step 2 was accepted on 2026-08-14 and provides a `NavigationSplitView` library shell with isolated in-memory sample books, grid/list presentations, search, sorting, and per-window transient state.
- Step 3 was accepted on 2026-08-14. It replaced the sample-data seam with UUID domain values, the normalized GRDB schema, ordered migrations, repository access, live observations, and database-backed library projections.
- Step 4 was accepted on 2026-08-15. It adds native book creation, details, and metadata editing; ordered author persistence; validation; favorite and recently-opened state; persisted search and sorting; and the complete Trash, restore, and explicit permanent-delete workflow.
- Step 4 reuses the normalized Step 3 schema without a new migration or dependency. Cover art remains generated library artwork until the Step 5 asset subsystem is authorized.
- Step 4A was accepted on 2026-08-15. The reader-first navigation correction keeps the sidebar and gives the remaining main-window space to grid/list browsing. Book activation uses the future reader seam, while every item owns its More menu and book information/management sheets. Until Step 9 supplies the reader, activation presents an explicit unavailable message and does not update `lastOpenedAt`.
- Step 4A also removes language, publisher, and publication-date metadata end to end through the ordered v2 migration. Added and Updated remain part of Book Info.
- Step 4A keeps cover artwork in grid and detail contexts but omits it from the compact list, where the reduced images were not legible enough to aid browsing.
- The production database resolves to `iEvelyn/Library.sqlite` under the app sandbox's Application Support directory and uses foreign keys plus WAL. Unit/integration tests use in-memory or temporary databases, and UI tests explicitly select an in-memory launch mode.
- Sample seeding and library reset exist only in Debug builds. Release builds contain neither the commands nor the sample provider.
- Xcode 26.6 is installed on `/Volumes/galfrey`, selected as the active developer directory, and provides Swift 6.3.3.
- Xcode Derived Data is configured under `/Volumes/galfrey/Xcode/DerivedData` to keep build output on the external volume.
- The app uses the product name iEvelyn, bundle identifier `org.cysun.iEvelyn`, macOS 26 deployment target, Swift 6 language mode with complete strict-concurrency checking, and App Sandbox with user-selected read/write file access.
- The legacy source application remains in a separate `Evelyn.NET` folder and should be consulted only when migration work reaches Steps 14–15 or when a specific legacy-data question must be answered.

## Open decisions

Resolve these at the named milestone or when the user chooses to decide sooner:

- Accepted Markdown extensions and raw-HTML behavior: Step 8.
- Continuous scrolling only versus an additional paginated/column reading mode: Step 9.
- Required EPUB language and any export-only publication metadata must be supplied by exporter policy or at export time rather than restored as stored book fields: Step 12.
- Notes attached to bookmarks in the initial release: Step 10.
- Whether old bookmarks and reading progress are reliable enough to migrate: Step 14.
- App icon, signing identity, distribution path, and notarization details: Step 16.

## Decision discipline

Do not casually reopen the fixed technical direction while implementing a step. If new evidence requires a change, document the evidence, impact on completed work, migration implications, and recommended decision before changing architecture. Keep this file updated when the user approves a material product or architecture decision.
