# EPUB validation workflow

iEvelyn targets EPUB 3.3 and generates EPUB files on demand. The in-project `EPUBExportTests` inspect archive order and compression, XML/XHTML well-formedness, required container files, manifest/spine consistency, navigation, stable IDs, asset coverage, Unicode, preflight failures, cancellation, and deterministic re-export.

For a release or exporter change, also validate representative output with the W3C EPUBCheck production release:

1. Download and unpack EPUBCheck 5.3.0 (or a reviewed newer production release) from <https://github.com/w3c/epubcheck/releases> outside the repository.
2. Export one-chapter, multi-chapter, Unicode, cover, and in-book-image examples from iEvelyn.
3. Run `java -jar /path/to/epubcheck.jar "/path/to/Book.epub"` for each file.
4. Require exit status 0 and no `ERROR` or `FATAL` messages. Review every `WARNING` and `USAGE` message rather than suppressing it.
5. Open the same files in Apple Books and check metadata, cover artwork, table of contents, chapter order, formatting, images, and previous/next navigation.
