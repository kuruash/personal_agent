import Foundation

struct ListDirectoryTool: AgentTool {
    static let maximumEntryCount = 500

    let name = "list_directory"
    var description: String {
        "Lists the immediate files and folders inside an approved local directory. Use this when you need to inspect the contents of a known directory. This does not search recursively. Approved roots: \(policy.approvedRootPaths.joined(separator: ", "))."
    }
    let parameterSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "path": .object([
                "type": .string("string"),
                "description": .string("Absolute or tilde-prefixed path to an approved directory.")
            ])
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
            let directory = try policy.validate(path)
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { throw FileAccessError.expectedDirectory }

            let keys: Set<URLResourceKey> = [
                .isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey
            ]
            let contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: []
            )
            let entries = try contents.compactMap { entry -> JSONValue? in
                // Omit symlinks that resolve outside the allowlist.
                guard (try? policy.validate(entry.path)) != nil else { return nil }
                let metadata = try entry.resourceValues(forKeys: keys)
                var result: [String: JSONValue] = [
                    "name": .string(entry.lastPathComponent),
                    "type": .string(FileSystemToolSupport.type(for: entry, values: metadata)),
                    "modifiedAt": FileSystemToolSupport.iso8601(metadata.contentModificationDate)
                ]
                if metadata.isRegularFile == true, let size = metadata.fileSize {
                    result["sizeBytes"] = .number(Double(size))
                }
                return .object(result)
            }.sorted { lhs, rhs in
                guard case .object(let left) = lhs, case .string(let leftName) = left["name"],
                      case .object(let right) = rhs, case .string(let rightName) = right["name"] else { return false }
                return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
            }
            let returnedEntries = Array(entries.prefix(Self.maximumEntryCount))
            return .object([
                "path": .string(directory.path),
                "entries": .array(returnedEntries),
                "totalEntryCount": .number(Double(entries.count)),
                "truncated": .bool(entries.count > returnedEntries.count)
            ])
        } catch {
            throw FileSystemToolSupport.mapError(error)
        }
    }
}
