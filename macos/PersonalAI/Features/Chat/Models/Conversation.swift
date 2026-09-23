import Foundation

struct Conversation: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    var messages: [ConversationMessage]
    var modelHistory: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        messages: [ConversationMessage] = [],
        modelHistory: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.modelHistory = modelHistory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var hasMeaningfulContent: Bool {
        messages.contains { $0.role == .user && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
