import Foundation

enum ConversationRole: String, Codable, Sendable {
    case user
    case assistant
}

struct ConversationMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: ConversationRole
    let content: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: ConversationRole,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}
