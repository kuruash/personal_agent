import Foundation
import os
import UniformTypeIdentifiers

struct SearchFilesTool: AgentTool {
    static let defaultResultLimit = 50
    static let maximumResultLimit = 100
    static let visitedItemLimit = 10_000

    enum SortMode: String, CaseIterable {
        case modificationTimeDescending
        case modificationTimeAscending
        case nameAscending
        case nameDescending
    }

    private struct Candidate {
        let name: String
        let relativePath: String
        let type: String
        let fileType: String
        let sizeBytes: Int64?
        let modificationDate: Date?

        var jsonValue: JSONValue {
            .object([
                "name": .string(name),
                "filename": .string(name),
                "relativePath": .string(relativePath),
                "type": .string(type),
                "fileType": .string(fileType),
                "sizeBytes": sizeBytes.map { .number(Double($0)) } ?? .null,
                "modifiedAt": FileSystemToolSupport.iso8601(modificationDate)
            ])
        }
    }

    let name = "search_files"
    var description: String {
        "Searches recursively by filename inside an approved local directory. Results include relative paths and file metadata, and are sorted newest-first by default. Use modificationTimeDescending for latest/newest requests. PDF and DOCX names are searchable even though read_file does not parse those formats. Use read_file afterward only for supported text files. Approved roots: \(policy.approvedRootPaths.joined(separator: ", "))."
    }
    let parameterSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "query": .object(["type": .string("string"), "description": .string("Text to match in file or directory names.")]),
            "directory": .object(["type": .string("string"), "description": .string("Approved directory to search recursively.")]),
            "maxResults": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(100)]),
            "sortBy": .object([
                "type": .string("string"),
                "enum": .array(SortMode.allCases.map { .string($0.rawValue) }),
                "description": .string("Deterministic result ordering. Defaults to modificationTimeDescending.")
            ])
        ]),
        "required": .array([.string("query"), .string("directory")]),
        "additionalProperties": .bool(false)
    ])

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.personalai.app",
        category: "FileSearch"
    )
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
            let sortMode = try Self.sortMode(in: object)
            let directory = try policy.validate(directoryPath)
            guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw FileAccessError.expectedDirectory
            }

            let keys: Set<URLResourceKey> = [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                .contentTypeKey, .fileSizeKey, .contentModificationDateKey
            ]
            var enumerationError: Error?
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants],
                errorHandler: { _, error in
                    if enumerationError == nil { enumerationError = error }
                    return true
                }
            ) else { throw FileAccessError.unreadable("Could not enumerate the directory.") }

            var candidates: [Candidate] = []
            var visited = 0
            while let candidateURL = enumerator.nextObject() as? URL,
                  visited < Self.visitedItemLimit {
                visited += 1
                let values = try? candidateURL.resourceValues(forKeys: keys)
                if values?.isSymbolicLink == true,
                   (try? policy.validate(candidateURL.path)) == nil {
                    enumerator.skipDescendants()
                }
                guard candidateURL.lastPathComponent.range(
                    of: query,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) != nil,
                (try? policy.validate(candidateURL.path)) != nil,
                let values else { continue }

                let candidate = Candidate(
                    name: candidateURL.lastPathComponent,
                    relativePath: Self.relativePath(for: candidateURL, under: directory),
                    type: FileSystemToolSupport.type(for: candidateURL, values: values),
                    fileType: values.contentType?.identifier ?? Self.fallbackFileType(for: candidateURL, values: values),
                    sizeBytes: values.fileSize.map(Int64.init),
                    modificationDate: values.contentModificationDate
                )
                candidates.append(candidate)
                #if DEBUG
                Self.logger.debug("File search candidate relativePath=\(candidate.relativePath, privacy: .public) modifiedAt=\(candidate.modificationDate?.description ?? "unknown", privacy: .public)")
                #endif
            }

            if visited == 0, let enumerationError {
                throw FileSystemToolSupport.mapError(enumerationError)
            }

            let traversalLimitReached = visited == Self.visitedItemLimit
            let sorted = candidates.sorted { Self.isOrdered($0, before: $1, mode: sortMode) }
            let returned = Array(sorted.prefix(resultLimit))
            let limitReached = candidates.count > resultLimit || traversalLimitReached

            return .object([
                "query": .string(query),
                "directory": .string(directory.path),
                "results": .array(returned.map(\.jsonValue)),
                "candidateCount": .number(Double(candidates.count)),
                "returnedCount": .number(Double(returned.count)),
                "resultLimit": .number(Double(resultLimit)),
                "limitReached": .bool(limitReached),
                "sortMode": .string(sortMode.rawValue),
                "traversalLimitReached": .bool(traversalLimitReached)
            ])
        } catch {
            throw FileSystemToolSupport.mapError(error)
        }
    }

    private static func sortMode(in object: [String: JSONValue]) throws -> SortMode {
        guard let raw = object["sortBy"] else { return .modificationTimeDescending }
        guard case .string(let value) = raw, let mode = SortMode(rawValue: value) else {
            throw FileAccessError.malformedArguments(
                "sortBy must be one of: \(SortMode.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        return mode
    }

    private static func relativePath(for url: URL, under root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = url.standardizedFileURL.pathComponents
        return candidateComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private static func fallbackFileType(for url: URL, values: URLResourceValues) -> String {
        if values.isDirectory == true { return "directory" }
        let fileExtension = url.pathExtension.lowercased()
        return fileExtension.isEmpty ? "unknown" : fileExtension
    }

    private static func isOrdered(_ lhs: Candidate, before rhs: Candidate, mode: SortMode) -> Bool {
        switch mode {
        case .modificationTimeDescending:
            if lhs.modificationDate != rhs.modificationDate {
                return (lhs.modificationDate ?? .distantPast) > (rhs.modificationDate ?? .distantPast)
            }
            return comparePath(lhs.relativePath, rhs.relativePath)
        case .modificationTimeAscending:
            if lhs.modificationDate != rhs.modificationDate {
                return (lhs.modificationDate ?? .distantFuture) < (rhs.modificationDate ?? .distantFuture)
            }
            return comparePath(lhs.relativePath, rhs.relativePath)
        case .nameAscending:
            return comparePath(lhs.relativePath, rhs.relativePath)
        case .nameDescending:
            return comparePath(rhs.relativePath, lhs.relativePath)
        }
    }

    private static func comparePath(_ lhs: String, _ rhs: String) -> Bool {
        let comparison = lhs.compare(
            rhs,
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        if comparison == .orderedSame { return lhs < rhs }
        return comparison == .orderedAscending
    }
}
