# iEvelyn 1.1 user guide

iEvelyn is a private, local-first ebook library and reader for macOS 26 or
later. It has no account, cloud sync, analytics, advertising, or telemetry.

## Build a library

Choose **Add Book** in the toolbar or press **Command-Shift-N**. A complete-book
Markdown file is required. Its first-level heading is the book title,
third-level Author headings identify ordered authors, and second-level headings
begin chapters:

    # Book Title

    ### Author: First Author
    ### 作者：第二作者

    ## First Chapter

    Chapter text.

The editor starts with title, first author, content file, and cover. **Show More
Options** reveals subtitle, description, additional authors, and tags. JPEG,
PNG, and HEIC covers are supported.

After a book is added successfully, iEvelyn opens it immediately in the reader.
Saving changes through **Edit Book…** also reopens that book so the saved result
is ready to read and becomes the most recently opened library item.

Use a book's **More** menu to edit metadata, replace or append complete content,
replace or remove its cover, add or remove it from Favorites, move it to Trash,
clear its saved reading progress, or export it. Choose **Select** in an active
library collection to select multiple books or **Select All**, then export EPUB
or Markdown files, clear reading progress, or move the selected books to Trash.
Select All applies to the currently visible destination and author/tag filter.
Trash is recoverable until **Delete Permanently** is confirmed; **Empty Trash**
permanently removes every book currently in Trash after confirmation.

## Browse, search, and read

The sidebar provides All Books, Currently Reading, Recently Added, Favorites,
Authors, Tags, and Trash. Use **Command-1** and **Command-2** for grid and list
views, and **Command-Shift-L** for All Books. Presentation, sorting, destination,
and window geometry are restored per window. Recently Opened is the default sort
for a new window; choosing another sort keeps that choice for that window.

Library search covers titles, subtitles, authors, tags, chapter titles, and
chapter content. Search results open the matching reader location. Trash is
searched only while Trash is selected. Press **Command-F** to focus Library
search.

Opening a book creates a separate reader window with its sidebar collapsed and
the reader panel focused. Press **Left Arrow** or **Right Arrow** for the
previous or next chapter, **B** to add an unlabeled bookmark at the current
location, and **C** to expand or collapse the sidebar. Expanding the sidebar
moves focus to it so **Up Arrow** and **Down Arrow** navigate the chapter list;
collapsing it returns focus to the reader panel. The chapter-jump menu and
**Command-F** Find in Book are also keyboard accessible. Reading position and
appearance settings persist automatically.

## Supported Markdown and safety

iEvelyn renders headings, paragraphs, emphasis, strong emphasis,
strikethrough, inline and fenced code, block quotes, thematic breaks, ordered
and unordered lists, task lists, tables, links, line breaks, and registered
book images. Markdown remains the canonical source used by the reader and EPUB
export.

Raw HTML is shown as source text and never executed. Unsafe link schemes are
omitted. Remote images are not fetched. Only asset references registered to the
current book are rendered. Normal http, https, and mailto links open outside
the trusted book document.

## Export and interchange

- **Export EPUB…** creates an EPUB 3 ebook suitable for Apple Books and other
  conforming readers.
- **Export Markdown…** reconstructs the complete-book Markdown source. It does
  not include cover or in-book image bytes.
- Selection mode can export multiple EPUB or Markdown documents at once. The
  native exporter writes one correctly named file per selected book and does
  not publish a partial batch when any book fails preflight.
- **Back Up Library…** creates a versioned .ievelynlibrary snapshot containing
  the database and every authoritative asset, with record counts and SHA-256
  checksums.
- **Restore Library…** validates every entry, checksum, database relationship,
  count, and asset before atomically replacing the active library. If the
  database cannot open, use **Restore from Backup…** on the recovery screen.
- **Check Library Integrity** runs SQLite integrity and foreign-key checks,
  verifies stored assets, removes only unreferenced asset files, and rebuilds
  the disposable search index when the canonical database is healthy. It does
  not invent missing data or silently replace damaged assets.

Keep multiple backups on storage separate from the Mac. A backup is a
point-in-time snapshot, not continuous synchronization. Reader caches,
thumbnails, generated EPUB files, and migration reconciliation reports are
rebuildable or operational output and are not included.

## Legacy migration

**Import Legacy Library…** accepts the neutral .ievelynlegacy bundle produced
by the separate EvelynMigration utility. Review additions, skips, warnings, and
duplicate choices before importing. The import stages and validates a complete
candidate library before an atomic exchange.

Legacy users/authentication, generated HTML/EPUB, thumbnails, 3:4 covers, and
user-bound paragraph-index bookmarks/progress are intentionally excluded.
Original legacy author text is kept as one native author value. Every completed
import writes a reconciliation report under the library's Migration Reports
folder.

## Recovery and known limits

- If opening the library fails, try again first. If the database remains
  unavailable, restore a known-good .ievelynlibrary backup from the recovery
  screen. The backup is fully validated before the damaged library is touched,
  and failed activation swaps the previous directory back.
- A missing cover falls back to generated artwork. Use **Edit Book…** to choose
  the cover again or remove the broken reference.
- Backup, restore, and legacy import currently materialize their archives in
  memory. Very large libraries can temporarily require memory comparable to
  the database plus compressed and uncompressed assets.
- The reader uses continuous vertical scrolling; a paginated column mode is not
  included in version 1.1.
- iEvelyn 1.1 supports macOS 26 or later and has no built-in updater.

For the exact library bundle contract, see LIBRARY_BUNDLE_FORMAT.md. For the
legacy import contract, see LEGACY_IMPORT.md.
