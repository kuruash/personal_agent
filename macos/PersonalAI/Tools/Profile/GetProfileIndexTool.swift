import Foundation

struct GetProfileIndexTool: AgentTool {
    let name = "get_profile_index"
    let description = "Lists the structured Personal Profile sections that are currently available. Use this to discover profile context without retrieving the entire profile."
    let parameterSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([:]),
        "additionalProperties": .bool(false)
    ])
    let store: ProfileStore

    func execute(arguments: JSONValue) async throws -> JSONValue {
        _ = try ProfileToolSupport.objectArguments(arguments)
        let sections = try store.availableSections().map { JSONValue.string($0.rawValue) }
        return .object(["available_sections": .array(sections)])
    }
}
