import Foundation

final class ConversationRepository {
    private let database: DatabaseManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(database: DatabaseManager) {
        self.database = database
        encoder.outputFormatting = [.sortedKeys]
    }

    func loadConversations() throws -> [Conversation] {
        try database.read { connection in
            let conversationRows = try connection.query("""
                SELECT id, title, created_at, updated_at
                FROM conversations
                ORDER BY updated_at DESC, id ASC;
                """)
            return try conversationRows.map { row in
                try decodeConversation(row, connection: connection)
            }
        }
    }

    func loadConversation(id: UUID) throws -> Conversation? {
        try database.read { connection in
            guard let row = try connection.query(
                "SELECT id, title, created_at, updated_at FROM conversations WHERE id = ?;",
                bindings: [.text(id.uuidString)]
            ).first else { return nil }
            return try decodeConversation(row, connection: connection)
        }
    }

    func save(_ conversation: Conversation) throws {
        guard conversation.hasMeaningfulContent else { return }
        try database.transaction { connection in
            try save(conversation, connection: connection)
        }
    }

    func importConversations(_ conversations: [Conversation]) throws {
        let meaningful = conversations.filter(\.hasMeaningfulContent)
        guard !meaningful.isEmpty else { return }
        try database.transaction { connection in
            for conversation in meaningful {
                let exists = try connection.query(
                    "SELECT id FROM conversations WHERE id = ?;",
                    bindings: [.text(conversation.id.uuidString)]
                ).first != nil
                if !exists {
                    try save(conversation, connection: connection)
                }
            }
        }
    }

    func appendMessage(_ message: ConversationMessage, conversationID: UUID) throws {
        try database.transaction { connection in
            try connection.execute(
                "INSERT INTO messages (id, conversation_id, role, content, created_at) VALUES (?, ?, ?, ?, ?);",
                bindings: [
                    .text(message.id.uuidString), .text(conversationID.uuidString),
                    .text(message.role.rawValue), .text(message.content),
                    .text(RepositoryDate.encode(message.createdAt))
                ]
            )
            try connection.execute(
                "UPDATE conversations SET updated_at = ? WHERE id = ?;",
                bindings: [.text(RepositoryDate.encode(Date())), .text(conversationID.uuidString)]
            )
        }
    }

    func rename(id: UUID, title: String, updatedAt: Date = Date()) throws {
        try database.read { connection in
            try connection.execute(
                "UPDATE conversations SET title = ?, updated_at = ? WHERE id = ?;",
                bindings: [.text(title), .text(RepositoryDate.encode(updatedAt)), .text(id.uuidString)]
            )
        }
    }

    func delete(id: UUID) throws {
        try database.read { connection in
            try connection.execute("DELETE FROM conversations WHERE id = ?;", bindings: [.text(id.uuidString)])
        }
    }

    private func save(_ conversation: Conversation, connection: SQLiteConnection) throws {
        try connection.execute("""
            INSERT INTO conversations (id, title, created_at, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at;
            """, bindings: [
                .text(conversation.id.uuidString), .text(conversation.title),
                .text(RepositoryDate.encode(conversation.createdAt)),
                .text(RepositoryDate.encode(conversation.updatedAt))
            ])

        try connection.execute("DELETE FROM messages WHERE conversation_id = ?;", bindings: [.text(conversation.id.uuidString)])
        for message in conversation.messages {
            try connection.execute(
                "INSERT INTO messages (id, conversation_id, role, content, created_at) VALUES (?, ?, ?, ?, ?);",
                bindings: [
                    .text(message.id.uuidString), .text(conversation.id.uuidString),
                    .text(message.role.rawValue), .text(message.content),
                    .text(RepositoryDate.encode(message.createdAt))
                ]
            )
        }

        try connection.execute("DELETE FROM agent_messages WHERE conversation_id = ?;", bindings: [.text(conversation.id.uuidString)])
        for (sequence, message) in conversation.modelHistory.enumerated() {
            let data: Data
            do {
                data = try encoder.encode(message)
            } catch {
                throw DatabaseError.decodingFailed("Could not encode agent context.")
            }
            guard let payload = String(data: data, encoding: .utf8) else {
                throw DatabaseError.decodingFailed("Agent context was not UTF-8.")
            }
            try connection.execute(
                "INSERT INTO agent_messages (conversation_id, sequence, payload_json) VALUES (?, ?, ?);",
                bindings: [.text(conversation.id.uuidString), .integer(Int64(sequence)), .text(payload)]
            )
        }
    }

    private func decodeConversation(_ row: SQLiteRow, connection: SQLiteConnection) throws -> Conversation {
        guard let id = UUID(uuidString: try row.requiredText("id")) else {
            throw DatabaseError.decodingFailed("Invalid conversation identifier.")
        }
        let messageRows = try connection.query("""
            SELECT id, role, content, created_at
            FROM messages
            WHERE conversation_id = ?
            ORDER BY created_at ASC, rowid ASC;
            """, bindings: [.text(id.uuidString)])
        let messages = try messageRows.map { messageRow -> ConversationMessage in
            guard let messageID = UUID(uuidString: try messageRow.requiredText("id")),
                  let role = ConversationRole(rawValue: try messageRow.requiredText("role")) else {
                throw DatabaseError.decodingFailed("Invalid visible conversation message.")
            }
            return ConversationMessage(
                id: messageID,
                role: role,
                content: try messageRow.requiredText("content"),
                createdAt: try RepositoryDate.decode(messageRow.requiredText("created_at"))
            )
        }

        let agentRows = try connection.query("""
            SELECT payload_json FROM agent_messages
            WHERE conversation_id = ? ORDER BY sequence ASC;
            """, bindings: [.text(id.uuidString)])
        let modelHistory = try agentRows.map { agentRow -> ChatMessage in
            let payload = try agentRow.requiredText("payload_json")
            do {
                return try decoder.decode(ChatMessage.self, from: Data(payload.utf8))
            } catch {
                throw DatabaseError.decodingFailed("Could not decode agent context.")
            }
        }

        return Conversation(
            id: id,
            title: try row.requiredText("title"),
            messages: messages,
            modelHistory: modelHistory,
            createdAt: try RepositoryDate.decode(row.requiredText("created_at")),
            updatedAt: try RepositoryDate.decode(row.requiredText("updated_at"))
        )
    }
}
