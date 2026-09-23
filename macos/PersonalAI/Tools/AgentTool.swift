import Foundation

protocol AgentTool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameterSchema: JSONValue { get }

    func execute(arguments: JSONValue) async throws -> JSONValue
}

extension AgentTool {
    var definition: ToolDefinition {
        ToolDefinition(name: name, description: description, parameters: parameterSchema)
    }
}

enum AgentToolError: LocalizedError {
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message): message
        }
    }
}
