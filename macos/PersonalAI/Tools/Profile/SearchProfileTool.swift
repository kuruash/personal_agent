import Foundation

struct SearchProfileTool: AgentTool {
    let name = "search_profile"
    let description = "Searches the local structured Personal Profile across experience, skills, projects, education, credentials, preferences, and other profile sections. Returns bounded matches with section and record provenance."
    let parameterSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "query": .object(["type": .string("string"), "minLength": .number(1)]),
            "limit": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(50)])
        ]),
        "required": .array([.string("query")]),
        "additionalProperties": .bool(false)
    ])
    let store: ProfileStore

    func execute(arguments: JSONValue) async throws -> JSONValue {
        let object = try ProfileToolSupport.objectArguments(arguments)
        let query = try ProfileToolSupport.string("query", in: object)
        let requestedLimit: Int
        if case .number(let value) = object["limit"] {
            requestedLimit = min(max(Int(value), 1), 50)
        } else {
            requestedLimit = 20
        }
        let results = try store.search(query, limit: requestedLimit)
        return .object([
            "query": .string(query),
            "results": try ProfileToolSupport.encode(results)
        ])
    }
}
