# iEvelyn Library Bundle Format

Format version: 1

An iEvelyn library backup is a ZIP archive with the `.ievelynlibrary` filename extension. The app registers that extension as the exported `org.cysun.iEvelyn.library-bundle` type conforming to `public.zip-archive`; backup filenames provide only a basename so the system save panel appends the extension exactly once. Restore also accepts an older bundle whose filename accidentally contains the extension twice because its final extension still resolves to the registered type. It is a portable, versioned snapshot of the canonical local library. Reader caches, cover thumbnails, generated EPUB files, and other rebuildable output are excluded.

## Archive layout

```text
manifest.json
Library.sqlite
Assets/
  Books/
    <book-uuid>/
      <asset-uuid>.<extension>
```

`Library.sqlite` is created with SQLite's online backup API so it represents one consistent database snapshot even when the active database uses WAL. Every asset referenced by that snapshot is included at its database-recorded relative path. No unreferenced or cache file is included.

## Manifest

`manifest.json` is UTF-8 JSON with stable, sorted keys and these fields:

- `formatIdentifier`: always `org.cysun.iEvelyn.library-bundle`.
- `formatVersion`: currently `1`.
- `createdAt`: an ISO-8601 UTC timestamp.
- `appVersion` and `appBuild`: the producing application version.
- `counts`: record counts for books, authors, author links, chapters, assets, tags, tag links, reading progress, and bookmarks.
- `database`: the database archive path, byte count, and lowercase SHA-256 checksum.
- `assets`: stable asset/book UUIDs, relative path, media type, byte count, and lowercase SHA-256 checksum for each authoritative asset.

The manifest does not checksum itself. ZIP CRC checks protect archive transport; the manifest SHA-256 values provide the application-level integrity boundary for the database and every asset.

## Restore rules

iEvelyn rejects archives with missing, duplicate, absolute, parent-traversing, extra, or unsupported-version entries. Before the active library is touched, restore verifies all recorded sizes and SHA-256 checksums, opens and migrates the database in a temporary sibling directory, runs SQLite integrity and foreign-key checks, compares record counts, compares asset metadata with the database, and rechecks every authoritative asset.

After validation, iEvelyn closes the active database and uses the macOS same-volume atomic directory-exchange operation to swap the staged and active library roots. If the restored library cannot reopen, the directories are exchanged back before the previous library is reopened. A rejected or interrupted restore therefore leaves the current library in place.

## Markdown interchange

Per-book Markdown export is intentionally simpler than a full-library bundle. It reconstructs the Step 9A complete-book source format: one level-1 title, ordered level-3 `Author:` headings, then ordered level-2 chapter sections with canonical Markdown. It does not include cover or in-book asset bytes; use a library bundle when those must travel with the source.
