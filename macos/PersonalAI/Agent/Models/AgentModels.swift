import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct ChatMessage: Codable, Equatable, Sendable {
    let role: String
    let content: String?
    let toolCalls: [ToolCall]?
    let toolCallID: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case role, content, name
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }

    init(
        role: String,
        content: String? = nil,
        toolCalls: [ToolCall]? = nil,
        toolCallID: String? = nil,
        name: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.name = name
    }
}

struct ToolDefinition: Codable, Equatable, Sendable {
    let type: String
    let function: FunctionDefinition

    init(name: String, description: String, parameters: JSONValue) {
        type = "function"
        function = FunctionDefinition(name: name, description: description, parameters: parameters)
    }
}

struct FunctionDefinition: Codable, Equatable, Sendable {
    let name: String
    let description: String
    let parameters: JSONValue
}

struct ToolCall: Codable, Equatable, Sendable {
    let id: String
    let type: String
    let function: ToolCallFunction
}

struct ToolCallFunction: Codable, Equatable, Sendable {
    let name: String
    /// OpenAI-compatible APIs return function arguments as a JSON-encoded string.
    let arguments: String
}

struct ChatCompletionRequest: Codable, Sendable {
    let model: String
    let messages: [ChatMessage]
    let tools: [ToolDefinition]?
    let toolChoice: String?

    enum CodingKeys: String, CodingKey {
        case model, messages, tools
        case toolChoice = "tool_choice"
    }
}

struct ChatCompletionResponse: Codable, Sendable {
    let choices: [ChatChoice]
    let usage: ChatUsage?

    init(choices: [ChatChoice], usage: ChatUsage? = nil) {
        self.choices = choices
        self.usage = usage
    }
}

struct ChatUsage: Codable, Equatable, Sendable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

struct ChatChoice: Codable, Sendable {
    let message: ChatMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

struct ModelsResponse: Codable, Sendable {
    let data: [AvailableModel]
}

struct AvailableModel: Codable, Equatable, Sendable {
    let id: String
}

struct APIErrorEnvelope: Codable {
    let error: APIErrorBody
}

struct APIErrorBody: Codable {
    let message: String
}
