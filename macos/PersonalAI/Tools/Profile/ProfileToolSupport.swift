import Foundation

enum ProfileToolSupport {
    static func objectArguments(_ arguments: JSONValue) throws -> [String: JSONValue] {
        guard case .object(let object) = arguments else {
            throw AgentToolError.invalidArguments("Arguments must be a JSON object.")
        }
        return object
    }

    static func string(_ key: String, in object: [String: JSONValue]) throws -> String {
        guard case .string(let value) = object[key],
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentToolError.invalidArguments("\(key) must be a non-empty string.")
        }
        return value
    }

    static func encode<T: Encodable>(_ value: T) throws -> JSONValue {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try JSONDecoder().decode(JSONValue.self, from: encoder.encode(value))
    }
}
