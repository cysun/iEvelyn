import Foundation
import GRDB
import SimpleTokenizer

nonisolated enum LibraryDatabaseLocation: Equatable, Sendable {
    case production(URL)
    case temporary(URL)
    case inMemory

    var databaseURL: URL? {
        switch self {
        case .production(let url), .temporary(let url):
            url
        case .inMemory:
            nil
        }
    }

    var isProduction: Bool {
        if case .production = self {
            return true
        }
        return false
    }
}

nonisolated struct LibraryDatabaseDiagnostics: Equatable, Sendable {
    let location: LibraryDatabaseLocation
    let foreignKeysEnabled: Bool
    let journalMode: String
    let appliedMigrations: [String]
}

nonisolated enum LibraryDatabaseError: LocalizedError, Equatable {
    case applicationSupportDirectoryUnavailable
    case foreignKeysDisabled
    case writeAheadLoggingUnavailable(actualMode: String)

    var errorDescription: String? {
        switch self {
        case .applicationSupportDirectoryUnavailable:
            "The Application Support directory is unavailable."
        case .foreignKeysDisabled:
            "The library database could not enable foreign-key enforcement."
        case .writeAheadLoggingUnavailable(let actualMode):
            "The library database could not enable write-ahead logging (current mode: \(actualMode))."
        }
    }
}

nonisolated final class LibraryDatabase: Sendable {
    static let productionDirectoryName = "iEvelyn"
    static let productionDatabaseName = "Library.sqlite"

    let writer: any DatabaseWriter
    let location: LibraryDatabaseLocation

    private init(writer: any DatabaseWriter, location: LibraryDatabaseLocation) throws {
        self.writer = writer
        self.location = location

        try LibrarySchema.migrator.migrate(writer)
        let diagnostics = try diagnosticsSynchronously()
        guard diagnostics.foreignKeysEnabled else {
            throw LibraryDatabaseError.foreignKeysDisabled
        }

        if location.databaseURL != nil, diagnostics.journalMode.lowercased() != "wal" {
            throw LibraryDatabaseError.writeAheadLoggingUnavailable(actualMode: diagnostics.journalMode)
        }
    }

    static func openProduction(fileManager: FileManager = .default) async throws -> LibraryDatabase {
        let url = try productionDatabaseURL(fileManager: fileManager)
        return try openDisk(at: url, location: .production(url), fileManager: fileManager)
    }

    static func makeTemporary(
        in directoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> LibraryDatabase {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let url = directoryURL.appending(path: productionDatabaseName, directoryHint: .notDirectory)
        return try openDisk(at: url, location: .temporary(url), fileManager: fileManager)
    }

    static func makeInMemory() throws -> LibraryDatabase {
        var configuration = databaseConfiguration()
        configuration.label = "iEvelyn.TestDatabase"
        let queue = try DatabaseQueue(configuration: configuration)
        return try LibraryDatabase(writer: queue, location: .inMemory)
    }

    static func productionDatabaseURL(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw LibraryDatabaseError.applicationSupportDirectoryUnavailable
        }

        return applicationSupportURL
            .appending(path: productionDirectoryName, directoryHint: .isDirectory)
            .appending(path: productionDatabaseName, directoryHint: .notDirectory)
    }

    func diagnostics() async throws -> LibraryDatabaseDiagnostics {
        try await writer.read { database in
            try Self.makeDiagnostics(database: database, location: self.location)
        }
    }

    func read<Value: Sendable>(
        _ access: @escaping @Sendable (Database) throws -> Value
    ) async throws -> Value {
        try await writer.read(access)
    }

    func write<Value: Sendable>(
        _ updates: @escaping @Sendable (Database) throws -> Value
    ) async throws -> Value {
        try await writer.write(updates)
    }

    private static func openDisk(
        at url: URL,
        location: LibraryDatabaseLocation,
        fileManager: FileManager
    ) throws -> LibraryDatabase {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var configuration = databaseConfiguration()
        configuration.label = "iEvelyn.LibraryDatabase"
        configuration.journalMode = .wal
        let pool = try DatabasePool(path: url.path, configuration: configuration)
        return try LibraryDatabase(writer: pool, location: location)
    }

    static func databaseConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.busyMode = .timeout(5)
        configuration.prepareDatabase { database in
            let result = ievelyn_register_simple_tokenizer(database.sqliteConnection)
            guard result == 0 else {
                throw LibrarySearchError.tokenizerRegistrationFailed(code: result)
            }
        }
        return configuration
    }

    private func diagnosticsSynchronously() throws -> LibraryDatabaseDiagnostics {
        try writer.read { database in
            try Self.makeDiagnostics(database: database, location: location)
        }
    }

    private static func makeDiagnostics(
        database: Database,
        location: LibraryDatabaseLocation
    ) throws -> LibraryDatabaseDiagnostics {
        let foreignKeysEnabled = try Int.fetchOne(database, sql: "PRAGMA foreign_keys") == 1
        let journalMode = try String.fetchOne(database, sql: "PRAGMA journal_mode") ?? "unknown"
        let appliedMigrations = try LibrarySchema.migrator.appliedMigrations(database)

        return LibraryDatabaseDiagnostics(
            location: location,
            foreignKeysEnabled: foreignKeysEnabled,
            journalMode: journalMode,
            appliedMigrations: appliedMigrations
        )
    }
}
