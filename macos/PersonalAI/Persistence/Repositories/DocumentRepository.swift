import Foundation

final class DocumentRepository {
    private let database: DatabaseManager

    init(database: DatabaseManager) { self.database = database }

    func listDocuments() throws -> [DocumentMetadata] {
        try database.read { connection in
            try connection.query("SELECT * FROM documents ORDER BY updated_at DESC;").map(decode)
        }
    }

    func getDocument(id: UUID) throws -> DocumentMetadata? {
        try database.read { connection in
            try connection.query("SELECT * FROM documents WHERE id = ?;", bindings: [.text(id.uuidString)])
                .first.map(decode)
        }
    }

    func saveDocumentMetadata(_ document: DocumentMetadata) throws {
        try database.read { connection in
            try connection.execute("""
                INSERT INTO documents (id, type, name, file_path, mime_type, is_primary, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET type=excluded.type, name=excluded.name,
                    file_path=excluded.file_path, mime_type=excluded.mime_type,
                    is_primary=excluded.is_primary, updated_at=excluded.updated_at;
                """, bindings: [
                    .text(document.id.uuidString), .text(document.type), .text(document.name),
                    document.filePath.sqliteValue, document.mimeType.sqliteValue,
                    .integer(document.isPrimary ? 1 : 0),
                    .text(RepositoryDate.encode(document.createdAt)), .text(RepositoryDate.encode(document.updatedAt))
                ])
        }
    }

    func deleteDocumentMetadata(id: UUID) throws {
        try database.read { connection in
            try connection.execute("DELETE FROM documents WHERE id = ?;", bindings: [.text(id.uuidString)])
        }
    }

    private func decode(_ row: SQLiteRow) throws -> DocumentMetadata {
        guard let id = UUID(uuidString: try row.requiredText("id")) else {
            throw DatabaseError.decodingFailed("Invalid document identifier.")
        }
        return DocumentMetadata(
            id: id, type: try row.requiredText("type"), name: try row.requiredText("name"),
            filePath: row.text("file_path"), mimeType: row.text("mime_type"),
            isPrimary: row.integer("is_primary") == 1,
            createdAt: try RepositoryDate.decode(row.requiredText("created_at")),
            updatedAt: try RepositoryDate.decode(row.requiredText("updated_at"))
        )
    }
}
