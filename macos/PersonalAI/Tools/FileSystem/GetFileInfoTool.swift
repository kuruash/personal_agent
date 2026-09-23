import Foundation

struct GetFileInfoTool: AgentTool {
    let name = "get_file_info"
    let description = "Returns reliable filesystem metadata about a specific file or directory inside an approved local directory."
    let parameterSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "path": .object(["type": .string("string"), "description": .string("Path to an approved file or directory.")])
        ]),
        "required": .array([.string("path")]),
        "additionalProperties": .bool(false)
    ])

    private let policy: FileAccessPolicy

    init(policy: FileAccessPolicy = .shared) { self.policy = policy }

    func execute(arguments: JSONValue) async throws -> JSONValue {
        do {
            let object = try FileSystemToolSupport.objectArguments(arguments)
            let path = try FileSystemToolSupport.requiredString("path", in: object)
            let url = try policy.validate(path)
            let keys: Set<URLResourceKey> = [
                .isDirectoryKey, .isRegularFileKey, .fileSizeKey,
                .creationDateKey, .contentModificationDateKey
            ]
            let values = try url.resourceValues(forKeys: keys)
            var result: [String: JSONValue] = [
                "name": .string(url.lastPathComponent),
                "path": .string(url.path),
                "type": .string(FileSystemToolSupport.type(for: url, values: values)),
                "createdAt": FileSystemToolSupport.iso8601(values.creationDate),
                "modifiedAt": FileSystemToolSupport.iso8601(values.contentModificationDate)
            ]
            if let size = values.fileSize { result["sizeBytes"] = .number(Double(size)) }
            return .object(result)
        } catch {
            throw FileSystemToolSupport.mapError(error)
        }
    }
}
