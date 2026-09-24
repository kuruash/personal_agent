import Foundation

struct SaveMemoryTool: AgentTool {
    let name = "save_memory"
    let description = "Saves one durable local memory only when the user clearly asks to remember, save, or store it. Never use for inferred facts, transcripts, or silent background extraction. Identical normalized content is not duplicated."
    let parameterSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "content": .object(["type": .string("string"), "minLength": .number(1), "maxLength": .number(4_000)]),
            "type": .object(["type": .string("string"), "enum": .array(MemoryType.allCases.map { .string($0.rawValue) })]),
            "importance": .object(["type": .string("string"), "enum": .array(MemoryImportance.allCases.map { .string($0.rawValue) })])
        ]),
        "required": .array([.string("content"), .string("type")]),
        "additionalProperties": .bool(false)
    ])
    let store: MemoryStore

    func execute(arguments: JSONValue) async throws -> JSONValue {
        let object = try MemoryToolSupport.object(arguments, allowedKeys: ["content", "type", "importance"])
        let result = try store.create(
            content: MemoryToolSupport.string("content", in: object),
            type: try MemoryToolSupport.type(in: object)!,
            source: .agentTool,
            importance: try MemoryToolSupport.importance(in: object) ?? .normal
        )
        return .object([
            "status": .string(result.wasCreated ? "created" : "already_exists"),
            "memory": MemoryToolSupport.json(result.memory)
        ])
    }
}
