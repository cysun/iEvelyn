# iEvelyn Legacy Import

Step 15 imports the version 1 `.ievelynlegacy` neutral bundle produced by the
separate EvelynMigration utility. The native app never connects to PostgreSQL
and never treats legacy integer IDs as domain identifiers.

## Dry run and validation

`Library > Import Legacy Library…` reads the selected ZIP-conforming bundle and
performs a no-write dry run. Before offering Import, iEvelyn validates:

- the exact format identifier and supported version;
- safe, unique, complete archive paths with no undeclared files;
- manifest and report counts, byte counts, lowercase SHA-256 checksums, and
  legacy-ID mappings;
- strict UTF-8 JSON and canonical chapter Markdown;
- book, chapter, and asset ownership/reference consistency; and
- image bytes independently of the legacy content-type declaration.

The review sheet reports bundle counts, exporter and importer warnings, exporter
skips, likely duplicate books, and the additions implied by the selected
duplicate strategy. A title-and-author match is only a warning heuristic. The
user must explicitly choose whether to skip likely duplicates or import another
copy; iEvelyn never merges books silently. If duplicate-relevant library state
changes after the dry run, the reviewed plan is rejected and must be reviewed
again.

## Native mapping

- Every imported book, chapter, and owned asset record receives a new UUID.
- A legacy book's unsplit `author` value is preserved as one native author
  string. The source has no reliable multi-author structure to split.
- Ordered chapters use the exporter's `(legacyNumber, legacyID)` order and are
  stored as zero-based native positions.
- Chapter Markdown remains canonical. Validated legacy `Files/View/<id>` and
  `Files/Download/<id>` references are rewritten to owned
  `book-asset://<book-uuid>/<asset-uuid>` URLs.
- Because native assets belong to one book, a legacy image referenced by more
  than one imported book receives a separate owned asset record and file for
  each book.
- Legacy notes, soft-delete state, update time, and optional last-viewed time
  are retained where the native model has an honest equivalent. Last-viewed
  maps only to `lastOpenedAt`; no reading position is fabricated.
- Blank titles, authors, or chapter names receive stable fallback values and a
  reconciliation warning.

Legacy 3:4 covers, thumbnails, generated HTML/EPUB, users/authentication, and
paragraph-index bookmarks/progress remain excluded exactly as reported by the
exporter. Imported books therefore use generated cover artwork until the user
adds new 2:3 covers.

## Commit and rollback boundary

The importer first creates a temporary sibling of the active Application
Support library. It uses SQLite's online backup API for the current database,
copies and verifies every authoritative current asset, retains prior legacy
reconciliation reports, writes imported owned assets, inserts all new records in
one database transaction, rebuilds the complete search index, and renders every
imported chapter through the current controlled reader renderer. The complete
candidate then passes SQLite integrity, foreign-key, and asset-checksum checks.

Only a validated candidate can replace the active library. Activation uses
macOS's atomic directory exchange after the active database closes. If the new
library cannot reopen, the same exchange restores the previous root before it
is reopened. Failure or cancellation before activation removes the disposable
candidate and leaves the active library unchanged.

## Reconciliation reports

Each completed import writes a new JSON report under:

```text
Application Support/iEvelyn/Migration Reports/Legacy Import <uuid>.json
```

Reports retain the source-bundle checksum and snapshot metadata, source and
export counts, the chosen duplicate strategy, imported/skipped/rebuilt counts,
all legacy-to-native UUID mappings, and exporter/importer/render warnings. They
do not contain chapter Markdown, database credentials, users, or private source
paths. Later legacy imports retain earlier reports.

The current `.ievelynlibrary` backup format protects canonical database and
asset data but does not include migration reports. Preserve a report separately
if it is needed as a long-term audit artifact after restoring a backup.

## Current scale characteristic

Bundle selection and validation currently materialize the selected archive and
validated payloads in memory. Peak memory therefore scales with compressed and
uncompressed bundle size. Large-library profiling and any streaming redesign
belong to Step 16; no production library or source database is used by importer
tests.
