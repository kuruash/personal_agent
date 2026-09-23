import Foundation

struct SearchFilesTool: AgentTool {
    static let defaultResultLimit = 50
    static let maximumResultLimit = 100
    static let visitedItemLimit = 10_000

    let name = "search_files"
    var description: String {
        "Searches recursively for files and directories whose names match a query inside an approved local directory. Matching is case-insensitive. Use read_file afterward when the contents of a matched text file are needed. Approved roots: \(policy.approvedRootPaths.joined(separator: ", "))."
    }
    let parameterSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "query": .object(["type": .string("string"), "description": .string("Text to match in file or directory names.")]),
            "directory": .object(["type": .string("string"), "description": .string("Approved directory to search recursively.")]),
            "maxResults": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(100)])
        ]),
        "required": .array([.string("query"), .string("directory")]),
        "additionalProperties": .bool(false)
    ])

    private let policy: FileAccessPolicy

    init(policy: FileAccessPolicy = .shared) { self.policy = policy }

    func execute(arguments: JSONValue) async throws -> JSONValue {
        do {
            let object = try FileSystemToolSupport.objectArguments(arguments)
            let query = try FileSystemToolSupport.requiredString("query", in: object)
            let directoryPath = try FileSystemToolSupport.requiredString("directory", in: object)
            let resultLimit = try FileSystemToolSupport.optionalInteger(
                "maxResults", in: object, default: Self.defaultResultLimit,
                range: 1...Self.maximumResultLimit
            )
            let directory = try policy.validate(directoryPath)
            guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw FileAccessError.expectedDirectory
            }

            let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            var enumerationError: Error?
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.skipsPackageDescendants],
                errorHandler: { _, error in
                    if enumerationError == nil { enumerationError = error }
                    return true
                }
            ) else { throw FileAccessError.unreadable("Could not enumerate the directory.") }

            var results: [JSONValue] = []
            var visited = 0
            while let candidate = enumerator.nextObject() as? URL,
                  visited < Self.visitedItemLimit,
                  results.count < resultLimit {
                visited += 1
                let values = try? candidate.resourceValues(forKeys: Set(keys))
                if values?.isSymbolicLink == true {
                    if (try? policy.validate(candidate.path)) == nil { enumerator.skipDescendants() }
                }
                guard candidate.lastPathComponent.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil,
                      (try? policy.validate(candidate.path)) != nil,
                      let values else { continue }
                results.append(.object([
                    "name": .string(candidate.lastPathComponent),
                    "path": .string(candidate.standardizedFileURL.resolvingSymlinksInPath().path),
                    "type": .string(FileSystemToolSupport.type(for: candidate, values: values))
                ]))
            }

            if visited == 0, let enumerationError {
                throw FileSystemToolSupport.mapError(enumerationError)
            }

            return .object([
                "query": .string(query),
                "directory": .string(directory.path),
                "results": .array(results),
                "resultLimit": .number(Double(resultLimit)),
                "limitReached": .bool(results.count == resultLimit || visited == Self.visitedItemLimit)
            ])
        } catch {
            throw FileSystemToolSupport.mapError(error)
        }
    }
}
