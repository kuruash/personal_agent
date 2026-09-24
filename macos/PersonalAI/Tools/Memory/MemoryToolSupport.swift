import Foundation

enum MemoryToolSupport {
    static func object(
        _ arguments: JSONValue,
        allowedKeys: Set<String>
    ) throws -> [String: JSONValue] {
        guard case .object(let object) = arguments else {
            throw AgentToolError.invalidArguments("Arguments must be a JSON object.")
        }
        let unexpected = Set(object.keys).subtracting(allowedKeys)
        guard unexpected.isEmpty else {
            throw AgentToolError.invalidArguments("Unexpected arguments: \(unexpected.sorted().joined(separator: ", ")).")
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

    static func optionalString(_ key: String, in object: [String: JSONValue]) throws -> String? {
        guard let value = object[key] else { return nil }
        guard case .string(let string) = value,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentToolError.invalidArguments("\(key) must be a non-empty string.")
        }
        return string
    }

    static func type(_ key: String = "type", in object: [String: JSONValue], required: Bool = true) throws -> MemoryType? {
        guard let raw = object[key] else {
            if required { throw AgentToolError.invalidArguments("\(key) is required.") }
            return nil
        }
        guard case .string(let value) = raw, let type = MemoryType(rawValue: value) else {
            throw AgentToolError.invalidArguments("Invalid memory type.")
        }
        return type
    }

    static func importance(in object: [String: JSONValue], required: Bool = false) throws -> MemoryImportance? {
        guard let raw = object["importance"] else {
            if required { throw AgentToolError.invalidArguments("importance is required.") }
            return nil
        }
        guard case .string(let value) = raw, let importance = MemoryImportance(rawValue: value) else {
            throw AgentToolError.invalidArguments("Invalid memory importance.")
        }
        return importance
    }

    static func id(in object: [String: JSONValue]) throws -> UUID {
        let raw = try string("id", in: object)
        guard let id = UUID(uuidString: raw) else {
            throw AgentToolError.invalidArguments("id must be a valid memory UUID.")
        }
        return id
    }

    static func limit(in object: [String: JSONValue], default defaultValue: Int) throws -> Int {
        guard let raw = object["limit"] else { return defaultValue }
        guard case .number(let number) = raw, number.rounded() == number,
              (1...50).contains(Int(number)) else {
            throw AgentToolError.invalidArguments("limit must be an integer from 1 through 50.")
        }
        return Int(number)
    }

    static func json(_ memory: MemoryRecord) -> JSONValue {
        .object([
            "id": .string(memory.id.uuidString),
            "type": .string(memory.type.rawValue),
            "content": .string(memory.content),
            "importance": .string(memory.importance.rawValue),
            "source": .string(memory.source.rawValue),
            "created_at": .string(RepositoryDate.encode(memory.createdAt)),
            "updated_at": .string(RepositoryDate.encode(memory.updatedAt))
        ])
    }
}
