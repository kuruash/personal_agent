import Foundation

struct TestTool: AgentTool {
    let name = "get_current_project"
    let description = "Returns information about the project currently being developed."
    let parameterSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([:]),
        "additionalProperties": .bool(false)
    ])

    func execute(arguments: JSONValue) async throws -> JSONValue {
        guard case .object(let values) = arguments, values.isEmpty else {
            throw AgentToolError.invalidArguments("get_current_project expects an empty JSON object.")
        }

        return .object([
            "name": .string("Personal AI"),
            "platform": .string("macOS"),
            "framework": .string("SwiftUI")
        ])
    }
}
