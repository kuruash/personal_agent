import Foundation

struct SearchMemoryTool: AgentTool {
    let name = "search_memory"
    let description = "Searches durable local Memory for relevant contextual information. Use Profile tools instead for stable structured Profile facts. Returns bounded deterministic matches and never invents missing memories."
    let parameterSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "query": .object(["type": .string("string"), "minLength": .number(1)]),
            "type": .object(["type": .string("string"), "enum": .array(MemoryType.allCases.map { .string($0.rawValue) })]),
            "limit": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(50)])
        ]),
        "required": .array([.string("query")]),
        "additionalProperties": .bool(false)
    ])
    let store: MemoryStore

    func execute(arguments: JSONValue) async throws -> JSONValue {
        let object = try MemoryToolSupport.object(arguments, allowedKeys: ["query", "type", "limit"])
        let results = try store.search(
            MemoryToolSupport.string("query", in: object),
            type: try MemoryToolSupport.type(in: object, required: false),
            limit: try MemoryToolSupport.limit(in: object, default: 10)
        )
        return .object(["results": .array(results.map(MemoryToolSupport.json))])
    }
}
