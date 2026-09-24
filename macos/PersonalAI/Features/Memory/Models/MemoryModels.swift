import Foundation

enum MemoryType: String, CaseIterable, Codable, Identifiable, Sendable {
    case preference, goal, project, decision, context, other

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum MemorySource: String, CaseIterable, Codable, Sendable {
    case userExplicit = "user_explicit"
    case agentTool = "agent_tool"
    case manualUI = "manual_ui"
}

enum MemoryImportance: String, CaseIterable, Codable, Identifiable, Sendable {
    case low, normal, high

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct MemoryRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var type: MemoryType
    var content: String
    var source: MemorySource
    var importance: MemoryImportance
    let createdAt: Date
    var updatedAt: Date
}

struct MemorySaveResult: Equatable, Sendable {
    let memory: MemoryRecord
    let wasCreated: Bool
}

enum MemoryError: LocalizedError, Equatable {
    case emptyContent
    case contentTooLong
    case notFound
    case duplicate(existingID: UUID)

    var errorDescription: String? {
        switch self {
        case .emptyContent: "Memory content cannot be empty."
        case .contentTooLong: "Memory content must be 4,000 characters or fewer."
        case .notFound: "The requested memory could not be found."
        case .duplicate: "An identical memory already exists."
        }
    }
}
