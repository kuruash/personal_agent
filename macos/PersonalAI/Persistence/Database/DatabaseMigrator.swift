import Foundation
import os

enum DatabaseMigrator {
    static let currentVersion = 1

    static func migrate(connection: SQLiteConnection, logger: Logger) throws {
        let currentVersion = Int(try connection.query("PRAGMA user_version;").first?.integer("user_version") ?? 0)
        #if DEBUG
        logger.notice("[Database] Current schema version: \(currentVersion, privacy: .public)")
        #endif

        guard currentVersion <= self.currentVersion else {
            throw DatabaseError.migrationFailed(
                "Database version \(currentVersion) is newer than supported version \(self.currentVersion)."
            )
        }

        if currentVersion < 1 {
            #if DEBUG
            logger.notice("[Database] Applying migration V1")
            #endif
            do {
                try connection.execute("BEGIN IMMEDIATE TRANSACTION;")
                try migrationV1(connection)
                try connection.execute("PRAGMA user_version = 1;")
                try connection.execute("COMMIT;")
                #if DEBUG
                logger.notice("[Database] Migration V1 completed")
                #endif
            } catch {
                try? connection.execute("ROLLBACK;")
                throw DatabaseError.migrationFailed(error.localizedDescription)
            }
        }
    }

    private static func migrationV1(_ database: SQLiteConnection) throws {
        try database.execute("""
            CREATE TABLE IF NOT EXISTS profile (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                full_name TEXT,
                preferred_name TEXT,
                location TEXT,
                email TEXT,
                phone TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """)
        try database.execute("""
            CREATE TABLE IF NOT EXISTS profile_links (
                id TEXT PRIMARY KEY,
                label TEXT NOT NULL,
                url TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """)
        try database.execute("""
            CREATE TABLE IF NOT EXISTS documents (
                id TEXT PRIMARY KEY,
                type TEXT NOT NULL,
                name TEXT NOT NULL,
                file_path TEXT,
                mime_type TEXT,
                is_primary INTEGER NOT NULL DEFAULT 0 CHECK (is_primary IN (0, 1)),
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """)
        try database.execute("CREATE INDEX IF NOT EXISTS idx_documents_type ON documents(type);")
        try database.execute("""
            CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """)
        try database.execute("CREATE INDEX IF NOT EXISTS idx_conversations_updated_at ON conversations(updated_at DESC);")
        try database.execute("""
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY,
                conversation_id TEXT NOT NULL,
                role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
                content TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
            );
            """)
        try database.execute("CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id, created_at);")
        try database.execute("""
            CREATE TABLE IF NOT EXISTS agent_messages (
                conversation_id TEXT NOT NULL,
                sequence INTEGER NOT NULL,
                payload_json TEXT NOT NULL,
                PRIMARY KEY (conversation_id, sequence),
                FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
            );
            """)
    }
}
