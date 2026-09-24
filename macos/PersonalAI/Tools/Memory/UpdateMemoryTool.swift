import Foundation

struct UpdateMemoryTool: AgentTool {
    let name = "update_memory"
    let description = "Updates a specific durable local memory using an ID returned by search_memory or list_memories. Never guess a memory ID."
    let parameterSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "id": .object(["type": .string("string")]),
            "content": .object(["type": .string("string"), "minLength": .number(1), "maxLength": .number(4_000)]),
            "type": .object(["type": .string("string"), "enum": .array(MemoryType.allCases.map { .string($0.rawValue) })]),
            "importance": .object(["type": .string("string"), "enum": .array(MemoryImportance.allCases.map { .string($0.rawValue) })])
        ]),
        "required": .array([.string("id")]),
        "additionalProperties": .bool(false)
    ])
    let store: MemoryStore

    func execute(arguments: JSONValue) async throws -> JSONValue {
        let object = try MemoryToolSupport.object(arguments, allowedKeys: ["id", "content", "type", "importance"])
        let id = try MemoryToolSupport.id(in: object)
        guard let existing = try store.memory(id: id) else { throw MemoryError.notFound }
        guard object["content"] != nil || object["type"] != nil || object["importance"] != nil else {
            throw AgentToolError.invalidArguments("At least one field to update is required.")
        }
        let updated = try store.update(
            id: id,
            content: try MemoryToolSupport.optionalString("content", in: object) ?? existing.content,
            type: try MemoryToolSupport.type(in: object, required: false) ?? existing.type,
            importance: try MemoryToolSupport.importance(in: object) ?? existing.importance
        )
        return .object(["status": .string("updated"), "memory": MemoryToolSupport.json(updated)])
    }
}
