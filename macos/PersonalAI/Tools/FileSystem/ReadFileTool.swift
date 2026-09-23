import Foundation

struct ReadFileTool: AgentTool {
    static let maximumContentBytes = 65_536
    static let supportedExtensions: Set<String> = [
        "txt", "md", "json", "csv", "swift", "py", "js", "ts", "tsx", "jsx",
        "html", "css", "yml", "yaml", "xml", "toml", "ini", "conf", "sh"
    ]

    let name = "read_file"
    let description = "Reads the textual contents of a supported plain-text or source-code file inside an approved local directory. It does not support PDF, DOCX, images, or other binary files. Large text files are truncated."
    let parameterSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "path": .object(["type": .string("string"), "description": .string("Path to a supported text file in an approved directory.")])
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
            guard Self.supportedExtensions.contains(url.pathExtension.lowercased()) else {
                throw FileAccessError.unsupportedFileType
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { throw FileAccessError.expectedFile }

            let size = values.fileSize ?? 0
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.maximumContentBytes + 1) ?? Data()
            let truncated = size > Self.maximumContentBytes || data.count > Self.maximumContentBytes
            var contentData = Data(data.prefix(Self.maximumContentBytes))
            guard !contentData.contains(0) else { throw FileAccessError.unsupportedFileType }

            var content: String?
            while !contentData.isEmpty, content == nil {
                content = String(data: contentData, encoding: .utf8)
                if content == nil, truncated { contentData.removeLast() }
                else if content == nil { throw FileAccessError.unreadable("File is not valid UTF-8 text.") }
            }
            guard let content else { throw FileAccessError.unreadable("File is not valid UTF-8 text.") }

            return .object([
                "path": .string(url.path),
                "content": .string(content),
                "truncated": .bool(truncated),
                "sizeBytes": .number(Double(size)),
                "returnedBytes": .number(Double(contentData.count))
            ])
        } catch {
            throw FileSystemToolSupport.mapError(error)
        }
    }
}
