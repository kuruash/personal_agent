import Foundation

struct DeleteMemoryTool: AgentTool {
    let name = "delete_memory"
    let description = "Deletes one durable local memory only when the user explicitly asks to forget or delete it. Use an ID returned by search_memory or list_memories; never guess IDs."
    let parameterSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object(["id": .object(["type": .string("string")])]),
        "required": .array([.string("id")]),
        "additionalProperties": .bool(false)
    ])
    let store: MemoryStore

    func execute(arguments: JSONValue) async throws -> JSONValue {
        let object = try MemoryToolSupport.object(arguments, allowedKeys: ["id"])
        let id = try MemoryToolSupport.id(in: object)
        try store.delete(id: id)
        return .object(["status": .string("deleted"), "id": .string(id.uuidString)])
    }
}
