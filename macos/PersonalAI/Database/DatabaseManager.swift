import Foundation
import SQLite3
import os

enum DatabaseError: LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case stepFailed(String)
    case migrationFailed(String)
    case decodingFailed(String)
    case transactionFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let detail): "Could not open the local database: \(detail)"
        case .prepareFailed(let detail): "Could not prepare a database operation: \(detail)"
        case .bindFailed(let detail): "Could not bind a database value: \(detail)"
        case .stepFailed(let detail): "Could not complete a database operation: \(detail)"
        case .migrationFailed(let detail): "Could not update the local database: \(detail)"
        case .decodingFailed(let detail): "Could not decode stored data: \(detail)"
        case .transactionFailed(let detail): "Could not complete a database transaction: \(detail)"
        }
    }
}

enum SQLiteValue {
    case text(String)
    case integer(Int64)
    case double(Double)
    case null
}

struct SQLiteRow {
    private let values: [String: String?]

    init(values: [String: String?]) {
        self.values = values
    }

    func text(_ column: String) -> String? { values[column] ?? nil }
    func requiredText(_ column: String) throws -> String {
        guard let value = text(column) else {
            throw DatabaseError.decodingFailed("Missing required column \(column).")
        }
        return value
    }
    func integer(_ column: String) -> Int64? {
        text(column).flatMap(Int64.init)
    }
}

final class SQLiteConnection {
    private let handle: OpaquePointer
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(handle: OpaquePointer) {
        self.handle = handle
    }

    func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw DatabaseError.stepFailed(errorMessage)
        }
    }

    func query(_ sql: String, bindings: [SQLiteValue] = []) throws -> [SQLiteRow] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)

        var rows: [SQLiteRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else {
                throw DatabaseError.stepFailed(errorMessage)
            }

            var values: [String: String?] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                guard let namePointer = sqlite3_column_name(statement, index) else { continue }
                let name = String(cString: namePointer)
                if sqlite3_column_type(statement, index) == SQLITE_NULL {
                    values[name] = .some(nil)
                } else if let valuePointer = sqlite3_column_text(statement, index) {
                    values[name] = String(cString: valuePointer)
                }
            }
            rows.append(SQLiteRow(values: values))
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw DatabaseError.prepareFailed(errorMessage)
        }
        return statement
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let text):
                result = sqlite3_bind_text(statement, index, text, -1, transient)
            case .integer(let integer):
                result = sqlite3_bind_int64(statement, index, integer)
            case .double(let double):
                result = sqlite3_bind_double(statement, index, double)
            case .null:
                result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else {
                throw DatabaseError.bindFailed(errorMessage)
            }
        }
    }

    private var errorMessage: String {
        String(cString: sqlite3_errmsg(handle))
    }
}

final class DatabaseManager {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.personalai.app",
        category: "PersonalAI.Database"
    )

    let databaseURL: URL
    private let queue = DispatchQueue(label: "com.personalai.database")
    private var handle: OpaquePointer?

    init(databaseURL: URL? = nil, fileManager: FileManager = .default) throws {
        self.databaseURL = try databaseURL ?? Self.defaultDatabaseURL(fileManager: fileManager)
        try fileManager.createDirectory(
            at: self.databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        debugLog("[Database] Opening database")
        debugLog("[Database] Database path: \(self.databaseURL.path)")

        var openedHandle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(self.databaseURL.path, &openedHandle, flags, nil) == SQLITE_OK,
              let openedHandle else {
            let detail = openedHandle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            if let openedHandle { sqlite3_close(openedHandle) }
            throw DatabaseError.openFailed(detail)
        }
        handle = openedHandle

        do {
            let connection = SQLiteConnection(handle: openedHandle)
            try connection.execute("PRAGMA foreign_keys = ON;")
            _ = try connection.query("PRAGMA journal_mode = WAL;")
            try DatabaseMigrator.migrate(connection: connection, logger: Self.logger)
            debugLog("[Database] Database ready")
        } catch {
            sqlite3_close(openedHandle)
            handle = nil
            throw error
        }
    }

    deinit {
        close()
    }

    func close() {
        queue.sync {
            guard let handle else { return }
            sqlite3_close(handle)
            self.handle = nil
        }
    }

    func read<T>(_ operation: (SQLiteConnection) throws -> T) throws -> T {
        try queue.sync {
            guard let handle else { throw DatabaseError.openFailed("The database is closed.") }
            return try operation(SQLiteConnection(handle: handle))
        }
    }

    func transaction<T>(_ operation: (SQLiteConnection) throws -> T) throws -> T {
        try queue.sync {
            guard let handle else { throw DatabaseError.openFailed("The database is closed.") }
            let connection = SQLiteConnection(handle: handle)
            try connection.execute("BEGIN IMMEDIATE TRANSACTION;")
            do {
                let result = try operation(connection)
                try connection.execute("COMMIT;")
                return result
            } catch {
                try? connection.execute("ROLLBACK;")
                throw DatabaseError.transactionFailed(error.localizedDescription)
            }
        }
    }

    private static func defaultDatabaseURL(fileManager: FileManager) throws -> URL {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw DatabaseError.openFailed("Application Support is unavailable.")
        }
        return applicationSupport
            .appendingPathComponent("PersonalAI", isDirectory: true)
            .appendingPathComponent("personal_ai.sqlite", isDirectory: false)
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        Self.logger.notice("\(message, privacy: .public)")
        #endif
    }
}
