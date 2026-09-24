import Foundation

struct ListMemoriesTool: AgentTool {
    let name = "list_memories"
    let description = "Lists a bounded set of durable local memories, optionally filtered by type. Use when the user asks what is remembered or asks for current remembered goals, preferences, projects, decisions, or context."
    let parameterSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "type": .object(["type": .string("string"), "enum": .array(MemoryType.allCases.map { .string($0.rawValue) })]),
            "limit": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(50)])
        ]),
        "additionalProperties": .bool(false)
    ])
    let store: MemoryStore

    func execute(arguments: JSONValue) async throws -> JSONValue {
        let object = try MemoryToolSupport.object(arguments, allowedKeys: ["type", "limit"])
        let results = try store.list(
            type: try MemoryToolSupport.type(in: object, required: false),
            limit: try MemoryToolSupport.limit(in: object, default: 20)
        )
        return .object(["results": .array(results.map(MemoryToolSupport.json))])
    }
}
