import Foundation
import os

enum DatabaseMigrator {
    static let currentVersion = 2

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

        if currentVersion < 2 {
            #if DEBUG
            logger.notice("[Database] Applying migration V2")
            #endif
            do {
                try connection.execute("BEGIN IMMEDIATE TRANSACTION;")
                try migrationV2(connection)
                try connection.execute("PRAGMA user_version = 2;")
                try connection.execute("COMMIT;")
                #if DEBUG
                logger.notice("[Database] Migration V2 completed")
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

    private static func migrationV2(_ database: SQLiteConnection) throws {
        try database.execute("""
            CREATE TABLE IF NOT EXISTS profile_identity (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                full_name TEXT NOT NULL,
                first_name TEXT NOT NULL,
                last_name TEXT NOT NULL,
                preferred_name TEXT NOT NULL,
                legal_name TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """)
        try database.execute("""
            CREATE TABLE IF NOT EXISTS profile_contact (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                primary_email TEXT NOT NULL,
                alternate_email TEXT,
                primary_phone TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """)
        try database.execute("""
            CREATE TABLE IF NOT EXISTS profile_address (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                street TEXT NOT NULL,
                city TEXT NOT NULL,
                state TEXT NOT NULL,
                postal_code TEXT NOT NULL,
                country TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """)
        try database.execute("""
            CREATE TABLE IF NOT EXISTS profile_education (
                id TEXT PRIMARY KEY,
                institution TEXT NOT NULL,
                degree TEXT NOT NULL,
                major TEXT NOT NULL,
                start_date TEXT NOT NULL,
                graduation_date TEXT NOT NULL,
                gpa REAL,
                coursework_json TEXT NOT NULL,
                activities_json TEXT NOT NULL,
                achievements_json TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """)
        try database.execute("""
            CREATE TABLE IF NOT EXISTS profile_experience (
                id TEXT PRIMARY KEY,
                company TEXT NOT NULL,
                title TEXT NOT NULL,
                employment_type TEXT NOT NULL,
                location TEXT NOT NULL,
                start_date TEXT NOT NULL,
                end_date TEXT,
                is_current INTEGER NOT NULL CHECK (is_current IN (0, 1)),
                achievements_json TEXT NOT NULL,
                technologies_json TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """)
        try database.execute("""
            CREATE TABLE IF NOT EXISTS profile_skills (
                category TEXT NOT NULL,
                skill TEXT NOT NULL,
                category_position INTEGER NOT NULL,
                position INTEGER NOT NULL,
                updated_at TEXT NOT NULL,
                PRIMARY KEY (category, skill)
            );
            """)
        try database.execute("""
            CREATE TABLE IF NOT EXISTS profile_projects (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                technologies_json TEXT NOT NULL,
                repository_url TEXT,
                description TEXT,
                highlights_json TEXT NOT NULL,
                position INTEGER NOT NULL,
                updated_at TEXT NOT NULL
            );
            """)
        try database.execute("""
            CREATE TABLE IF NOT EXISTS profile_certifications (
                id TEXT PRIMARY KEY,
                name TEXT,
                issuer TEXT,
                type TEXT,
                issue_date TEXT,
                expiration_date TEXT,
                credential_id TEXT,
                credential_url TEXT,
                unresolved INTEGER NOT NULL DEFAULT 0 CHECK (unresolved IN (0, 1)),
                updated_at TEXT NOT NULL
            );
            """)
        try database.execute("""
            CREATE TABLE IF NOT EXISTS profile_career_preferences (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                target_roles_json TEXT NOT NULL,
                preferred_locations_json TEXT NOT NULL,
                remote INTEGER NOT NULL CHECK (remote IN (0, 1)),
                hybrid INTEGER NOT NULL CHECK (hybrid IN (0, 1)),
                onsite INTEGER NOT NULL CHECK (onsite IN (0, 1)),
                willing_to_relocate INTEGER NOT NULL CHECK (willing_to_relocate IN (0, 1)),
                preferred_industries_json TEXT NOT NULL,
                earliest_start_date TEXT,
                updated_at TEXT NOT NULL
            );
            """)
        try database.execute("""
            CREATE TABLE IF NOT EXISTS profile_work_authorization (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                country TEXT NOT NULL,
                current_status TEXT,
                authorization_type TEXT,
                authorization_start_date TEXT,
                authorization_expiration_date TEXT,
                currently_required_sponsorship INTEGER NOT NULL CHECK (currently_required_sponsorship IN (0, 1)),
                future_required_sponsorship INTEGER NOT NULL CHECK (future_required_sponsorship IN (0, 1)),
                future_sponsorship_type TEXT,
                updated_at TEXT NOT NULL
            );
            """)
        try database.execute("""
            CREATE TABLE IF NOT EXISTS profile_application_answers (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                authorized_to_work_in_us INTEGER NOT NULL CHECK (authorized_to_work_in_us IN (0, 1)),
                requires_current_sponsorship INTEGER NOT NULL CHECK (requires_current_sponsorship IN (0, 1)),
                requires_future_sponsorship INTEGER NOT NULL CHECK (requires_future_sponsorship IN (0, 1)),
                willing_to_relocate INTEGER NOT NULL CHECK (willing_to_relocate IN (0, 1)),
                willing_to_work_onsite INTEGER NOT NULL CHECK (willing_to_work_onsite IN (0, 1)),
                willing_to_work_hybrid INTEGER NOT NULL CHECK (willing_to_work_hybrid IN (0, 1)),
                willing_to_work_remote INTEGER NOT NULL CHECK (willing_to_work_remote IN (0, 1)),
                updated_at TEXT NOT NULL
            );
            """)

        try database.execute("ALTER TABLE documents ADD COLUMN label TEXT;")
        try database.execute("ALTER TABLE documents ADD COLUMN filename TEXT;")
        try database.execute("ALTER TABLE documents ADD COLUMN last_updated TEXT;")
        try database.execute("UPDATE documents SET label = name WHERE label IS NULL;")
    }
}
