import GRDB

nonisolated enum LibrarySchema {
    static let initialMigrationIdentifier = "v1_create_library_schema"
    static let removePublicationMetadataMigrationIdentifier = "v2_remove_publication_metadata"
    static let fullTextSearchMigrationIdentifier = "v3_add_full_text_search"

    static var migrator: DatabaseMigrator {
        var migrator = versionOneMigrator
        migrator.registerMigration(
            removePublicationMetadataMigrationIdentifier,
            foreignKeyChecks: .immediate
        ) { database in
            for column in ["languageCode", "publisher", "publicationDate"] {
                try database.alter(table: "books") { table in
                    table.drop(column: column)
                }
            }
        }
        migrator.registerMigration(
            fullTextSearchMigrationIdentifier,
            foreignKeyChecks: .immediate
        ) { database in
            try database.execute(sql: fullTextSearchSchemaSQL)
            _ = try LibrarySearchIndexer.rebuildAll(database)
        }
        return migrator
    }

    static var versionOneMigrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(initialMigrationIdentifier, foreignKeyChecks: .immediate) { database in
            try database.execute(sql: initialSchemaSQL)
        }
        return migrator
    }

    private static let initialSchemaSQL = """
        CREATE TABLE books (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            title TEXT NOT NULL CHECK (length(trim(title)) > 0),
            subtitle TEXT,
            summary TEXT NOT NULL DEFAULT '',
            languageCode TEXT NOT NULL DEFAULT 'en'
                CHECK (length(trim(languageCode)) BETWEEN 2 AND 15),
            publisher TEXT,
            publicationDate INTEGER,
            isFavorite INTEGER NOT NULL DEFAULT 0 CHECK (isFavorite IN (0, 1)),
            trashedAt INTEGER,
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL,
            lastOpenedAt INTEGER
        );

        CREATE INDEX books_title ON books(title COLLATE NOCASE);
        CREATE INDEX books_createdAt ON books(createdAt DESC);
        CREATE INDEX books_lastOpenedAt ON books(lastOpenedAt DESC);
        CREATE INDEX books_favorites ON books(isFavorite) WHERE isFavorite = 1;
        CREATE INDEX books_trash ON books(trashedAt) WHERE trashedAt IS NOT NULL;

        CREATE TABLE authors (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            displayName TEXT NOT NULL CHECK (length(trim(displayName)) > 0),
            normalizedName TEXT NOT NULL UNIQUE CHECK (length(trim(normalizedName)) > 0),
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL
        );

        CREATE TABLE bookAuthors (
            bookID TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
            authorID TEXT NOT NULL REFERENCES authors(id) ON DELETE RESTRICT,
            position INTEGER NOT NULL CHECK (position >= 0),
            PRIMARY KEY (bookID, authorID),
            UNIQUE (bookID, position)
        ) WITHOUT ROWID;

        CREATE INDEX bookAuthors_authorID ON bookAuthors(authorID);

        CREATE TABLE chapters (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            bookID TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
            title TEXT NOT NULL CHECK (length(trim(title)) > 0),
            markdown TEXT NOT NULL DEFAULT '',
            position INTEGER NOT NULL CHECK (position >= 0),
            renderRevision INTEGER NOT NULL DEFAULT 0 CHECK (renderRevision >= 0),
            sourceHash TEXT,
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL,
            UNIQUE (bookID, position)
        );

        CREATE INDEX chapters_bookID ON chapters(bookID);

        CREATE TABLE assets (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            bookID TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
            chapterID TEXT REFERENCES chapters(id) ON DELETE SET NULL,
            purpose TEXT NOT NULL CHECK (purpose IN ('cover', 'chapterImage', 'attachment')),
            mediaType TEXT NOT NULL CHECK (length(trim(mediaType)) > 0),
            storageRelativePath TEXT NOT NULL UNIQUE CHECK (length(trim(storageRelativePath)) > 0),
            checksum TEXT NOT NULL CHECK (length(trim(checksum)) > 0),
            byteCount INTEGER NOT NULL CHECK (byteCount >= 0),
            pixelWidth INTEGER CHECK (pixelWidth IS NULL OR pixelWidth > 0),
            pixelHeight INTEGER CHECK (pixelHeight IS NULL OR pixelHeight > 0),
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL
        );

        CREATE INDEX assets_bookID ON assets(bookID);
        CREATE INDEX assets_chapterID ON assets(chapterID) WHERE chapterID IS NOT NULL;
        CREATE UNIQUE INDEX assets_one_cover_per_book ON assets(bookID) WHERE purpose = 'cover';

        CREATE TABLE tags (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            name TEXT NOT NULL CHECK (length(trim(name)) > 0),
            normalizedName TEXT NOT NULL UNIQUE CHECK (length(trim(normalizedName)) > 0),
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL
        );

        CREATE TABLE bookTags (
            bookID TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
            tagID TEXT NOT NULL REFERENCES tags(id) ON DELETE RESTRICT,
            PRIMARY KEY (bookID, tagID)
        ) WITHOUT ROWID;

        CREATE INDEX bookTags_tagID ON bookTags(tagID);

        CREATE TABLE readingProgress (
            bookID TEXT PRIMARY KEY NOT NULL REFERENCES books(id) ON DELETE CASCADE,
            chapterID TEXT REFERENCES chapters(id) ON DELETE SET NULL,
            stableBlockID TEXT,
            textQuote TEXT,
            contextBefore TEXT,
            contextAfter TEXT,
            fractionInChapter REAL CHECK (
                fractionInChapter IS NULL OR fractionInChapter BETWEEN 0.0 AND 1.0
            ),
            overallProgress REAL NOT NULL DEFAULT 0.0
                CHECK (overallProgress BETWEEN 0.0 AND 1.0),
            lastReadAt INTEGER NOT NULL
        ) WITHOUT ROWID;

        CREATE INDEX readingProgress_lastReadAt ON readingProgress(lastReadAt DESC);

        CREATE TABLE bookmarks (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            bookID TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
            chapterID TEXT REFERENCES chapters(id) ON DELETE SET NULL,
            stableBlockID TEXT,
            textQuote TEXT,
            contextBefore TEXT,
            contextAfter TEXT,
            fractionInChapter REAL CHECK (
                fractionInChapter IS NULL OR fractionInChapter BETWEEN 0.0 AND 1.0
            ),
            label TEXT,
            note TEXT,
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL
        );

        CREATE INDEX bookmarks_bookID_createdAt ON bookmarks(bookID, createdAt);
        CREATE INDEX bookmarks_chapterID ON bookmarks(chapterID) WHERE chapterID IS NOT NULL;

        CREATE TRIGGER assets_validate_chapter_book_insert
        BEFORE INSERT ON assets
        WHEN NEW.chapterID IS NOT NULL
             AND NOT EXISTS (
                 SELECT 1 FROM chapters
                 WHERE id = NEW.chapterID AND bookID = NEW.bookID
             )
        BEGIN
            SELECT RAISE(ABORT, 'asset chapter must belong to the same book');
        END;

        CREATE TRIGGER assets_validate_chapter_book_update
        BEFORE UPDATE OF bookID, chapterID ON assets
        WHEN NEW.chapterID IS NOT NULL
             AND NOT EXISTS (
                 SELECT 1 FROM chapters
                 WHERE id = NEW.chapterID AND bookID = NEW.bookID
             )
        BEGIN
            SELECT RAISE(ABORT, 'asset chapter must belong to the same book');
        END;

        CREATE TRIGGER readingProgress_validate_chapter_book_insert
        BEFORE INSERT ON readingProgress
        WHEN NEW.chapterID IS NOT NULL
             AND NOT EXISTS (
                 SELECT 1 FROM chapters
                 WHERE id = NEW.chapterID AND bookID = NEW.bookID
             )
        BEGIN
            SELECT RAISE(ABORT, 'reading progress chapter must belong to the same book');
        END;

        CREATE TRIGGER readingProgress_validate_chapter_book_update
        BEFORE UPDATE OF bookID, chapterID ON readingProgress
        WHEN NEW.chapterID IS NOT NULL
             AND NOT EXISTS (
                 SELECT 1 FROM chapters
                 WHERE id = NEW.chapterID AND bookID = NEW.bookID
             )
        BEGIN
            SELECT RAISE(ABORT, 'reading progress chapter must belong to the same book');
        END;

        CREATE TRIGGER bookmarks_validate_chapter_book_insert
        BEFORE INSERT ON bookmarks
        WHEN NEW.chapterID IS NOT NULL
             AND NOT EXISTS (
                 SELECT 1 FROM chapters
                 WHERE id = NEW.chapterID AND bookID = NEW.bookID
             )
        BEGIN
            SELECT RAISE(ABORT, 'bookmark chapter must belong to the same book');
        END;

        CREATE TRIGGER bookmarks_validate_chapter_book_update
        BEFORE UPDATE OF bookID, chapterID ON bookmarks
        WHEN NEW.chapterID IS NOT NULL
             AND NOT EXISTS (
                 SELECT 1 FROM chapters
                 WHERE id = NEW.chapterID AND bookID = NEW.bookID
             )
        BEGIN
            SELECT RAISE(ABORT, 'bookmark chapter must belong to the same book');
        END;
        """

    private static let fullTextSearchSchemaSQL = """
        CREATE TABLE librarySearchDocuments (
            id INTEGER PRIMARY KEY,
            documentKey TEXT NOT NULL UNIQUE,
            bookID TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
            chapterID TEXT REFERENCES chapters(id) ON DELETE CASCADE,
            stableBlockID TEXT,
            kind TEXT NOT NULL CHECK (kind IN ('metadata', 'chapterTitle', 'content')),
            ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
            fractionInChapter REAL NOT NULL DEFAULT 0.0
                CHECK (fractionInChapter BETWEEN 0.0 AND 1.0),
            title TEXT NOT NULL DEFAULT '',
            subtitle TEXT NOT NULL DEFAULT '',
            authors TEXT NOT NULL DEFAULT '',
            tags TEXT NOT NULL DEFAULT '',
            chapterTitle TEXT NOT NULL DEFAULT '',
            body TEXT NOT NULL DEFAULT ''
        );

        CREATE INDEX librarySearchDocuments_bookID
            ON librarySearchDocuments(bookID, ordinal, id);
        CREATE INDEX librarySearchDocuments_chapterID
            ON librarySearchDocuments(chapterID, ordinal, id)
            WHERE chapterID IS NOT NULL;

        CREATE VIRTUAL TABLE librarySearchIndex USING fts5(
            title,
            subtitle,
            authors,
            tags,
            chapterTitle,
            body,
            content='librarySearchDocuments',
            content_rowid='id',
            tokenize='simple 0'
        );

        CREATE TRIGGER librarySearchDocuments_after_insert
        AFTER INSERT ON librarySearchDocuments
        BEGIN
            INSERT INTO librarySearchIndex(
                rowid, title, subtitle, authors, tags, chapterTitle, body
            ) VALUES (
                NEW.id, NEW.title, NEW.subtitle, NEW.authors, NEW.tags,
                NEW.chapterTitle, NEW.body
            );
        END;

        CREATE TRIGGER librarySearchDocuments_after_delete
        AFTER DELETE ON librarySearchDocuments
        BEGIN
            INSERT INTO librarySearchIndex(
                librarySearchIndex, rowid, title, subtitle, authors, tags,
                chapterTitle, body
            ) VALUES (
                'delete', OLD.id, OLD.title, OLD.subtitle, OLD.authors, OLD.tags,
                OLD.chapterTitle, OLD.body
            );
        END;

        CREATE TRIGGER librarySearchDocuments_after_update
        AFTER UPDATE ON librarySearchDocuments
        BEGIN
            INSERT INTO librarySearchIndex(
                librarySearchIndex, rowid, title, subtitle, authors, tags,
                chapterTitle, body
            ) VALUES (
                'delete', OLD.id, OLD.title, OLD.subtitle, OLD.authors, OLD.tags,
                OLD.chapterTitle, OLD.body
            );
            INSERT INTO librarySearchIndex(
                rowid, title, subtitle, authors, tags, chapterTitle, body
            ) VALUES (
                NEW.id, NEW.title, NEW.subtitle, NEW.authors, NEW.tags,
                NEW.chapterTitle, NEW.body
            );
        END;
        """
}
