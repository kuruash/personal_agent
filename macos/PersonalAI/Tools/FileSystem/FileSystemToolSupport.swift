import Foundation

enum FileSystemToolSupport {
    static func objectArguments(_ arguments: JSONValue) throws -> [String: JSONValue] {
        guard case .object(let object) = arguments else {
            throw FileAccessError.malformedArguments("expected a JSON object")
        }
        return object
    }

    static func requiredString(_ key: String, in object: [String: JSONValue]) throws -> String {
        guard case .string(let value) = object[key],
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FileAccessError.malformedArguments("\(key) must be a non-empty string")
        }
        return value
    }

    static func optionalInteger(
        _ key: String,
        in object: [String: JSONValue],
        default defaultValue: Int,
        range: ClosedRange<Int>
    ) throws -> Int {
        guard let raw = object[key] else { return defaultValue }
        guard case .number(let number) = raw,
              number.rounded() == number,
              range.contains(Int(number)) else {
            throw FileAccessError.malformedArguments("\(key) must be an integer from \(range.lowerBound) through \(range.upperBound)")
        }
        return Int(number)
    }

    static func type(for url: URL, values: URLResourceValues) -> String {
        if values.isDirectory == true { return "directory" }
        if values.isRegularFile == true { return "file" }
        return "other"
    }

    static func iso8601(_ date: Date?) -> JSONValue {
        guard let date else { return .null }
        return .string(ISO8601DateFormatter().string(from: date))
    }

    static func mapError(_ error: Error) -> Error {
        if let accessError = error as? FileAccessError { return accessError }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(nsError.code) {
            return FileAccessError.permissionDenied
        }
        return FileAccessError.unreadable(error.localizedDescription)
    }
}
