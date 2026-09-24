import Foundation

final class MemoryRepository {
    private let database: DatabaseManager

    init(database: DatabaseManager) {
        self.database = database
    }

    func create(
        content: String,
        type: MemoryType,
        source: MemorySource,
        importance: MemoryImportance,
        id: UUID = UUID(),
        now: Date = Date()
    ) throws -> MemorySaveResult {
        let cleaned = try Self.cleanedContent(content)
        let normalized = Self.normalized(cleaned)
        return try database.read { connection in
            if let existing = try findNormalized(normalized, connection: connection) {
                return MemorySaveResult(memory: existing, wasCreated: false)
            }
            try connection.execute("""
                INSERT INTO memories
                    (id, type, content, normalized_content, source, importance, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """, bindings: [
                    .text(id.uuidString), .text(type.rawValue), .text(cleaned), .text(normalized),
                    .text(source.rawValue), .text(importance.rawValue),
                    .text(RepositoryDate.encode(now)), .text(RepositoryDate.encode(now))
                ])
            return MemorySaveResult(
                memory: MemoryRecord(
                    id: id, type: type, content: cleaned, source: source,
                    importance: importance, createdAt: now, updatedAt: now
                ),
                wasCreated: true
            )
        }
    }

    func get(id: UUID) throws -> MemoryRecord? {
        try database.read { connection in
            try load(id: id, connection: connection)
        }
    }

    func list(type: MemoryType? = nil, limit: Int = 50) throws -> [MemoryRecord] {
        try database.read { connection in
            let rows: [SQLiteRow]
            if let type {
                rows = try connection.query("""
                    SELECT id, type, content, source, importance, created_at, updated_at
                    FROM memories WHERE type = ?
                    ORDER BY updated_at DESC, created_at DESC, id ASC LIMIT ?;
                    """, bindings: [.text(type.rawValue), .integer(Int64(limit))])
            } else {
                rows = try connection.query("""
                    SELECT id, type, content, source, importance, created_at, updated_at
                    FROM memories
                    ORDER BY updated_at DESC, created_at DESC, id ASC LIMIT ?;
                    """, bindings: [.integer(Int64(limit))])
            }
            return try rows.map(Self.decode)
        }
    }

    func search(_ query: String, type: MemoryType? = nil, limit: Int = 20) throws -> [MemoryRecord] {
        let queryTokens = Self.tokens(query)
        guard !queryTokens.isEmpty else { return [] }
        let candidates = try list(type: type, limit: 10_000)
        return candidates.compactMap { memory -> (MemoryRecord, Int)? in
            let haystack = Self.normalized("\(memory.type.rawValue) \(memory.content)")
            let score = queryTokens.reduce(0) { $0 + (haystack.contains($1) ? 1 : 0) }
            return score > 0 ? (memory, score) : nil
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if lhs.0.importance != rhs.0.importance {
                return Self.importanceRank(lhs.0.importance) > Self.importanceRank(rhs.0.importance)
            }
            if lhs.0.updatedAt != rhs.0.updatedAt { return lhs.0.updatedAt > rhs.0.updatedAt }
            return lhs.0.id.uuidString < rhs.0.id.uuidString
        }
        .prefix(limit)
        .map(\.0)
    }

    func update(
        id: UUID,
        content: String,
        type: MemoryType,
        importance: MemoryImportance,
        source: MemorySource? = nil,
        now: Date = Date()
    ) throws -> MemoryRecord {
        let cleaned = try Self.cleanedContent(content)
        let normalized = Self.normalized(cleaned)
        return try database.read { connection in
            guard let existing = try load(id: id, connection: connection) else { throw MemoryError.notFound }
            if let duplicate = try findNormalized(normalized, connection: connection), duplicate.id != id {
                throw MemoryError.duplicate(existingID: duplicate.id)
            }
            let updatedSource = source ?? existing.source
            try connection.execute("""
                UPDATE memories
                SET type = ?, content = ?, normalized_content = ?, source = ?, importance = ?, updated_at = ?
                WHERE id = ?;
                """, bindings: [
                    .text(type.rawValue), .text(cleaned), .text(normalized),
                    .text(updatedSource.rawValue), .text(importance.rawValue),
                    .text(RepositoryDate.encode(now)), .text(id.uuidString)
                ])
            return MemoryRecord(
                id: id, type: type, content: cleaned, source: updatedSource,
                importance: importance, createdAt: existing.createdAt, updatedAt: now
            )
        }
    }

    func delete(id: UUID) throws {
        try database.read { connection in
            guard try load(id: id, connection: connection) != nil else { throw MemoryError.notFound }
            try connection.execute("DELETE FROM memories WHERE id = ?;", bindings: [.text(id.uuidString)])
        }
    }

    private func load(id: UUID, connection: SQLiteConnection) throws -> MemoryRecord? {
        try connection.query("""
            SELECT id, type, content, source, importance, created_at, updated_at
            FROM memories WHERE id = ?;
            """, bindings: [.text(id.uuidString)]).first.map(Self.decode)
    }

    private func findNormalized(_ normalized: String, connection: SQLiteConnection) throws -> MemoryRecord? {
        try connection.query("""
            SELECT id, type, content, source, importance, created_at, updated_at
            FROM memories WHERE normalized_content = ?;
            """, bindings: [.text(normalized)]).first.map(Self.decode)
    }

    private static func decode(_ row: SQLiteRow) throws -> MemoryRecord {
        guard let id = UUID(uuidString: try row.requiredText("id")),
              let type = MemoryType(rawValue: try row.requiredText("type")),
              let source = MemorySource(rawValue: try row.requiredText("source")),
              let importance = MemoryImportance(rawValue: try row.requiredText("importance")) else {
            throw DatabaseError.decodingFailed("Invalid memory record.")
        }
        return MemoryRecord(
            id: id, type: type, content: try row.requiredText("content"), source: source,
            importance: importance,
            createdAt: try RepositoryDate.decode(row.requiredText("created_at")),
            updatedAt: try RepositoryDate.decode(row.requiredText("updated_at"))
        )
    }

    private static func cleanedContent(_ content: String) throws -> String {
        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw MemoryError.emptyContent }
        guard cleaned.count <= 4_000 else { throw MemoryError.contentTooLong }
        return cleaned
    }

    static func normalized(_ content: String) -> String {
        content.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func tokens(_ query: String) -> [String] {
        normalized(query).split(separator: " ").map(String.init)
    }

    private static func importanceRank(_ importance: MemoryImportance) -> Int {
        switch importance { case .low: 0; case .normal: 1; case .high: 2 }
    }
}
