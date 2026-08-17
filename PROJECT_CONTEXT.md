# iEvelyn Project Context

Last updated: 2026-08-17

## Purpose of this document

This document preserves the product vision, architecture decisions, data strategy, and constraints for iEvelyn. It is the durable context for future work. Implementation sequencing and progress live in `IMPLEMENTATION_PLAN.md`; instructions for coding agents live in `AGENTS.md`.

## Product vision

iEvelyn is a completely new, native macOS application for managing, authoring, and reading a personal ebook library. The desired experience is closer to Apple Books than to an administrative database application, while also supporting author-focused capabilities such as importing structured book content and exporting EPUB files.

The existing Evelyn.NET application is a source of legacy book data only. Its web UI, ASP.NET controllers, authentication model, browser-based reader, database schema, and implementation patterns are not design constraints for iEvelyn.

## Product goals

- Deliver a polished, modern, macOS-only application using native conventions.
- Make the library pleasant to browse in grid and list forms.
- Provide a focused reading experience with themes, typography controls, navigation, search, progress, and bookmarks.
- Let the user create and update books from structured Markdown content files and manage metadata and covers through one book-level workflow.
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

The main window uses a native sidebar and a full browsing area rather than a persistent metadata column. Expected library sections include All Books, Currently Reading, Recently Added, Favorites, Authors, Tags, and Trash. Books can be displayed as cover grids or compact lists, searched, filtered, and sorted; Recently Opened is the default sort for a new window, while an explicitly chosen sort remains restored per window. Full-library search supports field scopes and location-aware results, while Authors and Tags expose counted filters. The cover grid uses artwork for visual browsing; the compact list omits tiny cover thumbnails and prioritizes title, author, library date, and progress. Activating a book opens the reader, and a successful Add or Edit operation immediately opens the saved book and records it as recently opened. Ordinary management actions belong to that book's compact More menu, with book changes presented in the unified Edit Book sheet rather than a separate information popup. An explicit selection mode may temporarily expose batch actions and Select All without making ordinary reader activation selection-dependent. The interface must have thoughtful empty, loading, and error states and work well in light and dark appearances.

### Book management and authoring

Adding a book uses one form for metadata, a required whole-book Markdown content file, and an optional cover. Editing uses the same form: omitting a content file preserves existing chapters, Replace consumes another complete book file, and Append adds chapter-only sections after the current last chapter. The form opens in a simple mode with title, one author, content, and cover; Show More Options reveals subtitle, description, ordered multi-author controls, and tag assignment without discarding values when it is turned off. There is no separate Book Info popup. Individual chapter management and editing—including adding, renaming, duplicating, deleting, reordering, importing, or directly editing a chapter—is not part of the current product workflow. Imported chapter structure remains visible through the reader's table of contents.

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

Step 11 adds an external-content SQLite FTS5 index for title/subtitle, ordered authors, tags, chapter titles, and semantic Markdown blocks. A repository-owned canonical rebuild can repair the index, while all product mutations that affect indexed data reindex the affected book inside the same GRDB transaction. Soft-deleted books remain indexed so an explicitly scoped Trash search works, but ordinary search excludes them. Bookmark labels and notes are intentionally absent from both the index and search APIs.

Chinese-first tokenization uses the audited no-pinyin core from Wang Fenjin's MIT-licensed `simple` v0.7.1 at commit `4ed008934495fc55ff4bf6620bba58311988b23e`. Because Apple's SQLite omits runtime extension loading and upstream does not ship a Swift package, the minimal tokenizer core is adapted as the local `Packages/SimpleTokenizer` SwiftPM target and registered directly on every GRDB SQLite connection. The target accepts only `simple 0`; pinyin code and dictionaries are not included, keeping the index smaller and making the no-pinyin decision compile-time explicit. Upstream updates require a source review plus migration, Unicode/search, performance, Debug/Release, and UI regression tests.

### Content model

- Markdown is the canonical editable representation of a chapter.
- Whole-book import accepts UTF-8 `.md`, `.markdown`, and `.txt` files. A complete file begins with a level-1 title followed by one or more consecutive level-3 author headings. Author text may be bare or use `Author:`, `Authors:`, `作者：`, or `作者:`. Level-2 headings define ordered chapters; a file without level-2 headings becomes one chapter named for the book.
- The complete-file H1/H3 preamble is validated against entered metadata and is not stored in a chapter body. Append files contain only one or more level-2 chapter sections and must start with the first chapter heading after optional blank lines.
- Add, complete replacement, append, metadata changes, and cover changes use repository transactions so validation or persistence failure cannot leave a partially updated book. Complete replacement preserves existing chapter UUIDs when deterministic matching is possible, protecting future reading anchors.
- Reader HTML and EPUB XHTML are derived representations generated from Markdown.
- Derived markup may be cached using a source hash and renderer-version key, but it must be safe to discard and rebuild.
- The accepted Markdown dialect and raw-HTML policy must be documented and covered by rendering tests.
- Use `swift-markdown` as the parser and build controlled renderers for reader HTML and EPUB XHTML.

Keeping both Markdown and HTML as independently editable database fields is explicitly avoided because the two representations can drift.

`swift-markdown` 0.8.0 and its `swift-cmark` 0.8.0 dependency are pinned through Swift Package Manager. The package is Apache-2.0 licensed with the Swift Runtime Library Exception. Because the package remains pre-1.0 and renderer behavior depends on its syntax tree, upgrades must be explicit and must rerun the rendering fixtures, structural tests, cache tests, Debug/Release builds, and preview UI smoke test. Step 8 defines the application dialect and rendering policy as follows:

- CommonMark plus GitHub-flavored tables, task lists, and strikethrough are supported. Smart punctuation follows the parser's defaults.
- Footnote syntax is not enabled and remains visible as literal source text rather than silently acquiring unstable semantics.
- Raw block and inline HTML is never trusted or executed. It is escaped, displayed as source, and accompanied by a visible preview warning.
- Text and attribute values are escaped by default. Reader and EPUB output are constructed separately; reader HTML carries a restrictive content-security policy, while EPUB output is well-formed XHTML.
- Links are limited to `http`, `https`, `mailto`, internal fragments, and validated book assets. Unsupported or unsafe destinations are removed while their labels remain visible.
- Images must resolve to an asset owned by the current book. Reader HTML retains a validated `book-asset://` URL serviced by the repository-backed WebKit handler, while EPUB XHTML uses a deterministic relative `../Assets/` path.
- Stable block anchors derive from the block kind and normalized semantic Markdown, with a deterministic occurrence suffix for duplicate blocks.
- Derived output is held only in a bounded in-memory cache keyed by source, renderer version, output mode, book, asset metadata, title, and language. It remains disposable and is never canonical data.

### Assets

- Store asset metadata and ownership in SQLite.
- Store cover images and chapter assets as files under the application's sandboxed Application Support directory.
- Use a 2:3 portrait aspect ratio for new cover artwork. Legacy 600x800 (3:4) cover files will not be migrated; replacement covers will be recreated for iEvelyn.
- Address assets by stable UUIDs, never by user-supplied file names alone.
- Copy imported files atomically, validate supported media types, and generate disposable thumbnails or render caches as needed.
- Rendering should use an application-specific asset URL mechanism such as `book-asset://` instead of exposing arbitrary local paths.

### EPUB

- ZIPFoundation 0.9.20 is pinned through Swift Package Manager for archive creation. It is MIT-licensed, supports the installed Swift/Xcode toolchain, and has no additional Apple-platform package dependencies. Upgrades must be explicit and must rerun archive-structure tests, EPUBCheck, Debug/Release builds, and the UI export smoke test.
- The `mimetype` entry must be first and uncompressed.
- Export must use generated EPUB-safe XHTML rather than reader HTML copied verbatim.
- Export should include structural tests and validation guidance; Apple Books is a required manual interoperability check.
- EPUB exports use the stable book UUID as their publication identifier and `und` (undetermined) as the standards-required language because language is intentionally absent from the canonical library model. No publication date or publisher is invented. `dcterms:modified` derives deterministically from the book's library update timestamp.
- The exporter packages only assets referenced by rendered chapters plus the current cover. JPEG, PNG, and GIF remain in their supported EPUB forms; HEIC and HEIF are converted to PNG during export without changing the authoritative library asset. Missing, corrupt, unsupported, or unsafe-to-render content blocks export before the save panel appears.
- Archive entries use stable paths, a fixed ZIP timestamp, and deterministic ordering. EPUB output remains rebuildable and is never written back into the library database or asset store.

### Legacy migration

- Migration is a one-time, explicit workflow, not runtime compatibility code.
- Build a separate .NET console exporter in `/Users/cysun/git/EvelynMigration` during Step 14.
- The exporter reads the old PostgreSQL database through a dedicated SELECT-only login, verifies a repeatable-read `READ ONLY` transaction, and writes a neutral, documented `.ievelynlegacy` bundle.
- Legacy bookmarks and automatic reading progress are excluded: both are user-bound paragraph numbers over generated HTML and cannot be represented honestly as the semantic Markdown anchors used by iEvelyn. Their aggregate counts and the exclusion reason remain in migration reports.
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
| `Bookmark` | Unlabeled semantic reading anchor and timestamps; nullable label and note fields are reserved without current product UI |

Use UUIDs for new domain identities. Store ordering explicitly. Use foreign keys and transactions for multi-record changes such as chapter reordering or permanent book deletion.

Initial schema decisions:

- Store UUIDs as lowercase 36-character text so database inspection and migration reports remain readable.
- Store dates as integer milliseconds since the Unix epoch and decode them through one shared GRDB record policy.
- The v2 migration removes language, publisher, and publication-date columns. iEvelyn's online self-published serials retain Added and Updated as library metadata instead of publication metadata.
- The v3 migration creates canonical search documents, an external-content FTS5 index using `simple 0`, synchronization triggers, and a transactional initial rebuild for existing books.
- Enforce nonempty titles/names, normalized unique author and tag names, unique ordered author/chapter positions, progress ranges, nonnegative asset sizes, and one cover-purpose asset per book.
- Model a book's cover through its unique owned `Asset` whose purpose is `cover`, avoiding a circular book/asset foreign key.
- Cascade permanent book deletion through owned joins, chapters, assets, progress, and bookmarks. Restrict deletion of authors or tags while linked to a book.
- Set chapter references on assets, reading progress, and bookmarks to null when a chapter is deleted, preserving book-level ownership and anchor fallback. Triggers reject cross-book chapter references.
- Keep the existing nullable bookmark label and note columns reserved for compatibility, but do not expose either in the current product. Step 10 bookmarks are always unlabeled.
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
├── Migration Reports/
│   └── Legacy Import <uuid>.json
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
- Import useful book metadata, ordered chapters, and referenced in-book content assets. Do not export or import legacy 600x800 cover images; covers will be recreated at iEvelyn's 2:3 ratio.
- Do not migrate legacy bookmarks/progress: the inspected implementation stores user-bound generated-HTML paragraph indices, which are not reliable semantic Markdown anchors. Report aggregate counts and the explicit exclusion instead.
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

As of 2026-08-17:

- `/Users/cysun/git/iEvelyn` is a Git repository on `main`, tracking `origin/main`; Step 1 was accepted on 2026-08-14.
- The native SwiftUI project, app target, Swift Testing target, and XCTest UI-test target exist, and the Step 1 manual checkpoint passed.
- Step 2 was accepted on 2026-08-14 and provides a `NavigationSplitView` library shell with isolated in-memory sample books, grid/list presentations, search, sorting, and per-window transient state.
- Step 3 was accepted on 2026-08-14. It replaced the sample-data seam with UUID domain values, the normalized GRDB schema, ordered migrations, repository access, live observations, and database-backed library projections.
- Step 4 was accepted on 2026-08-15. It adds native book creation, details, and metadata editing; ordered author persistence; validation; favorite and recently-opened state; persisted search and sorting; and the complete Trash, restore, and explicit permanent-delete workflow.
- Step 4 reuses the normalized Step 3 schema without a new migration or dependency. That schema's owned `Asset` records and unique cover constraint also support Step 5 without another migration.
- Step 4A was accepted on 2026-08-15. The reader-first navigation correction keeps the sidebar and gives the remaining main-window space to grid/list browsing. Book activation uses the future reader seam, while every item owns its More menu. Its original Book Info sheet was later removed during Step 9A. Until Step 9 supplied the reader, activation presented an explicit unavailable message and did not update `lastOpenedAt`.
- Step 4A also removed language, publisher, and publication-date metadata end to end through the ordered v2 migration.
- Step 4A keeps cover artwork in grid and detail contexts but omits it from the compact list, where the reduced images were not legible enough to aid browsing.
- Step 5 was accepted on 2026-08-15. It imports readable JPEG, PNG, and HEIC covers through the SwiftUI file importer; copies authoritative originals atomically into UUID-addressed per-book storage; persists checksums, byte counts, dimensions, media types, and relative paths; and renders disposable PNG thumbnails in the grid while retaining generated artwork as fallback and keeping the compact list text-led. Thumbnail data loads lazily for visible cover views through a bounded in-memory cache so large libraries do not eagerly retain every cover.
- Step 5 also defines the database-backed `book-asset://<book-uuid>/<asset-uuid>` resolution boundary, repairs orphaned files on launch, reports missing or failed cleanup, and removes owned storage after cover replacement/removal or permanent book deletion. It adds no third-party dependency and requires no schema change.
- Step 5 isolates one narrow AppKit bridge in `BookCoverArtwork`: `NSImage` decodes generated thumbnail data because SwiftUI does not provide a data-backed macOS `Image` initializer. File selection, layout, state, and controls remain SwiftUI.
- Step 6 was accepted on 2026-08-15 with individual chapter-management controls. Step 9A later removed those product controls in favor of whole-book import, replacement, and append; stable chapter identities and the transactional persistence foundations remain.
- Step 6 reused the Step 3 chapter schema without a migration or dependency.
- Step 7 was accepted on 2026-08-15 with a direct Markdown chapter editor. Step 9A later removed that product UI because content changes now occur at the whole-book level.
- Step 7 keeps Markdown canonical and saves through an ordered, debounced repository boundary with optimistic render-revision checks. Chapter switching and dismissal flush pending edits, newer edits cannot be overwritten by an older save, conflicts preserve the local draft until the user reloads stored content or explicitly overwrites it, and recoverable failures expose retry/revert actions. Metrics are computed off the main actor. The step adds no schema migration or dependency.
- Step 8 was accepted on 2026-08-15. It replaces the editor placeholder with a debounced live preview built on the macOS 26 SwiftUI WebKit integration. JavaScript is disabled, website data is nonpersistent, top-level navigation is restricted to the generated document, and book assets are loaded only after repository ownership validation. The sandboxed WebKit content process requires the outgoing-connections client entitlement even for the generated local document; iEvelyn does not initiate remote fetches, and the renderer's content-security policy and navigation policy continue to prevent book content from turning that entitlement into network access.
- Step 8 adds one controlled renderer with separate reader HTML and EPUB XHTML modes, deterministic block anchors, accessible light/dark CSS, explicit warnings for unsafe or unsupported input, and fixture coverage for GFM markup, Unicode, assets, malformed input, raw HTML, output structure, stable IDs, cache invalidation, and cancellation. It adds no schema migration.
- Step 9 was accepted on 2026-08-15. Book activation now opens a dedicated typed reader window. Each reader window owns its selected chapter, table-of-contents visibility, find presentation, rendering state, and errors, while typography and theme preferences are deliberately shared through `UserDefaults` so changes persist across reader windows and launches. The reader relies on the native split-view sidebar control, and Page Width is a proportional setting with a generous readable-line cap so the text column grows as the window widens without becoming unbounded on very large displays.
- Step 9 uses continuous vertical chapter scrolling. The optional CSS column/paginated mode was evaluated and deferred because it would complicate resizing, keyboard/trackpad behavior, and VoiceOver reading order without being required for the core reader. Native macOS full screen and vertical WebView scrolling supply predictable window and trackpad behavior.
- Step 9 Find in Book continues to scan the already-loaded chapters within one open reader. Step 11 separately replaces broad main-library filtering with transactional FTS5 indexing and location-aware cross-book results.
- Step 9A was accepted on 2026-08-16. It corrects the authoring workflow before Step 10: Add Book now requires a whole-book Markdown/text file and optionally accepts a cover; Edit Book can preserve, replace, or append content and also owns cover changes. The unified form defaults to its simple title/single-author/content/cover presentation, with subtitle, description, and ordered multi-author controls behind Show More Options. Complete files support English, Chinese, or bare level-3 author headings, while append files contain level-2 chapter sections only. The separate Book Info sheet and all product-facing individual chapter management/editing controls were removed. The change reuses the existing schema and dependencies.
- Step 10 was accepted on 2026-08-16. The reader debounces progress writes, restores the last chapter and semantic location, updates last-read time and overall progress for Currently Reading, and supports one-click unlabeled bookmark creation, direct navigation, and deletion. Stable block anchors fall back through quoted text, nearby context, and chapter fraction after whole-book replacement, while append preserves existing anchors.
- Step 10 keeps book-content JavaScript disabled and WebKit data nonpersistent. The app calls its own small capture/restore helpers in WebKit's default client content world so book source cannot execute those helpers or interpolate into executable JavaScript. Bookmark labels and notes remain outside the product; their existing nullable fields are reserved and the current repository boundary always stores null. The step adds no schema migration or dependency.
- Step 11 was accepted on 2026-08-16. It adds Chinese-first FTS5 search with the compile-time no-pinyin `simple 0` tokenizer, scoped highlighted snippets, direct semantic reader navigation, transactional whole-book Replace/Append and metadata index updates, deliberate Trash search, counted Author/Tag filters, tag assignment in the unified book editor, and a Debug-only canonical repair command. Bookmark fields remain outside the index and the one-click unlabeled bookmark workflow is unchanged.
- Step 12 was accepted on 2026-08-16. Per-book actions prepare a deterministic EPUB 3.3 package off the main actor, run metadata/render/asset preflight, and then present SwiftUI's user-selected file exporter. Packages contain stable metadata, a title/cover page, EPUB navigation, external CSS, ordered XHTML chapters, manifest/spine entries, and referenced supported assets. ZIPFoundation 0.9.20 is the only new dependency; no schema migration was required. Structural tests and W3C EPUBCheck 5.3.0 validate text-only and Unicode cover/image fixtures, and the Apple Books interoperability checkpoint passed.
- Step 13 was accepted on 2026-08-16. The documented `.ievelynlibrary` format packages a consistent SQLite online-backup snapshot and every authoritative asset with stable paths, record counts, producer version/timestamp metadata, byte counts, and SHA-256 checksums. The app exports that extension as a ZIP-conforming Uniform Type Identifier so save panels append it exactly once and restore panels recognize both new single-extension bundles and bundles created before that correction with the extension duplicated. Restore rejects unsafe paths, duplicates, missing/extra files, mismatched sizes/checksums/counts, invalid database relationships, and unsupported versions before constructing a temporary sibling library. A validated library replaces the active root with macOS's atomic directory exchange; a reopen failure exchanges the previous root back before reopening it.
- Step 13 also adds a Library menu Check Library Integrity command that removes only orphaned asset files, rebuilds the disposable search index when the canonical database is healthy, and reports remaining database/asset problems without claiming they were repaired. Per-book Markdown export reconstructs the complete Step 9A title, ordered authors, and ordered canonical chapters but intentionally excludes asset bytes. Backup and restore currently materialize the archive in memory, so peak memory scales with bundle size. The step reuses GRDB, CryptoKit, and the accepted ZIPFoundation dependency, with no schema migration or new dependency.
- Step 14 was accepted on 2026-08-16 after a successful live export from the separate `/Users/cysun/git/EvelynMigration` project. The neutral format identifier is `org.cysun.iEvelyn.legacy-export`, version 1, with the `.ievelynlegacy` extension. Stable legacy-ID paths, fixed ZIP metadata, source-derived timestamps, sorted JSON, SHA-256 checksums, counts, warnings, skipped items, and ID mappings make repeated unchanged exports deterministic. Original valid UTF-8 chapter Markdown is preserved without HTML recovery; recognized `Files/View/<id>` and `Files/Download/<id>` references map separately to neutral asset entries. Users/authentication, aggregate Markdown, generated HTML/EPUB, thumbnails, 3:4 covers, and paragraph-index bookmarks/progress are explicitly excluded and reported. Release/formatter checks, 14 fixture tests, the current dependency-vulnerability scan, and a disposable PostgreSQL end-to-end source-digest check pass.
- Step 15 was accepted on 2026-08-16 after the exported legacy library imported successfully. `Library > Import Legacy Library…` validates the complete neutral archive before presenting a no-write additions/skips/warnings/conflicts review. Likely title-and-author duplicates require an explicit skip-or-import-copy choice, and duplicate-relevant changes after review invalidate the plan. Import clones the current database and authoritative assets into a temporary sibling, creates new UUIDs, rewrites validated legacy asset routes, preserves the unsplit legacy author as one native author, rebuilds search, validates current reader rendering, and atomically exchanges the fully validated candidate with rollback on reopen failure. Each successful import retains prior reports and writes a new permanent reconciliation JSON file under `Migration Reports`; `.ievelynlibrary` backups do not currently include those reports. The archive and validated payloads are materialized in memory, with large-library profiling deferred to Step 16. No schema migration or dependency was added. Debug/Release builds and all 110 tests (99 unit/integration and 11 UI) pass. See `LEGACY_IMPORT.md` for the complete contract.
- Reader markup remains generated by the Step 8 renderer with JavaScript disabled and nonpersistent WebKit data. Only WebKit's exact internal `about:blank` document URL (plus fragments) is trusted for top-level navigation; explicit `http`, `https`, and `mailto` link activations are routed to the system outside the book context, and other navigation is blocked.
- The production database resolves to `iEvelyn/Library.sqlite` under the app sandbox's Application Support directory and uses foreign keys plus WAL. Unit/integration tests use in-memory or temporary databases, and UI tests explicitly select an in-memory launch mode.
- Sample seeding and library reset exist only in Debug builds. Release builds contain neither the commands nor the sample provider.
- Xcode 26.6 is installed on `/Volumes/galfrey`, selected as the active developer directory, and provides Swift 6.3.3.
- Xcode Derived Data is configured under `/Volumes/galfrey/Xcode/DerivedData` to keep build output on the external volume.
- The app uses the product name iEvelyn, bundle identifier `org.cysun.iEvelyn`, macOS 26 deployment target, Swift 6 language mode with complete strict-concurrency checking, and App Sandbox with user-selected read/write file access plus outgoing connections required by the WebKit content process.
- The legacy source application remains in a separate `Evelyn.NET` folder and should be consulted only when migration work reaches Steps 14–15 or when a specific legacy-data question must be answered.

- Step 16 targets a direct-download version 1.0 build 1 release credited to Chengyu Sun. The app keeps App Sandbox, adds Hardened Runtime, and will use a Developer ID Application signature, secure timestamp, Apple notarization, stapling, Gatekeeper validation, and a checksummed ZIP. Signing and notarization credentials remain outside source control. The original app icon is a centered cream open book and amber bookmark on deep indigo; About uses a narrow AppKit bridge to display the running app icon because SwiftUI has no equivalent API.
- New reader windows open with the sidebar collapsed and the reader panel focused. Bare `B`, Left Arrow, and Right Arrow add a bookmark or move between chapters; bare `C` toggles the sidebar. Expanding the sidebar focuses its current list, while collapsing it returns focus to the WebKit reader. An isolated AppKit bridge supplies window-scoped bare-key monitoring and first-responder requests because SwiftUI's macOS 26 WebView integration does not expose those capabilities reliably; text-entry responders are excluded. The reader keyboard and focus correction was manually accepted on 2026-08-17.
- Step 17 was accepted on 2026-08-17 as the version 1.1 build 2 functional milestone. Its explicit per-window selection mode applies Select All to the currently visible destination and author/tag filter; batch export writes one EPUB or complete Markdown file per selected active book through SwiftUI's native multi-document exporter. Batch Trash moves and Empty Trash use validated database transactions, with asset cleanup reported separately if filesystem removal is incomplete. Clear Reading Progress deletes only the saved progress row, preserving bookmarks and Recently Opened history. Recently Opened is the default sort for new windows, and successful Add/Edit saves immediately open the saved book and update its recently-opened timestamp. The step adds no schema migration or dependency.

## Open decisions

Resolve these at the named milestone or when the user chooses to decide sooner:

- Whether a future release should add an accessible paginated/column alternative to the continuous reader.
- A future release-hosting location and update mechanism remain undecided; version 1.0 is a manually distributed direct-download ZIP.

## Decision discipline

Do not casually reopen the fixed technical direction while implementing a step. If new evidence requires a change, document the evidence, impact on completed work, migration implications, and recommended decision before changing architecture. Keep this file updated when the user approves a material product or architecture decision.
