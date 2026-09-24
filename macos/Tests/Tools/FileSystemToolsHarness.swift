import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case .failed(let message): message }
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure.failed(message) }
}

private func object(_ value: JSONValue) throws -> [String: JSONValue] {
    guard case .object(let result) = value else { throw TestFailure.failed("Expected JSON object") }
    return result
}

private func array(_ value: JSONValue?) throws -> [JSONValue] {
    guard case .array(let result) = value else { throw TestFailure.failed("Expected JSON array") }
    return result
}

private func string(_ value: JSONValue?) throws -> String {
    guard case .string(let result) = value else { throw TestFailure.failed("Expected JSON string") }
    return result
}

private func expectError(_ expected: FileAccessError, operation: () async throws -> Void) async throws {
    do {
        try await operation()
        throw TestFailure.failed("Expected \(expected.localizedDescription)")
    } catch let error as FileAccessError {
        try require(error == expected, "Expected \(expected), received \(error)")
    }
}

@main
private struct FileSystemToolsHarness {
    static func main() async throws {
        let manager = FileManager.default
        let testRoot = manager.temporaryDirectory.appendingPathComponent("PersonalAI-FilesystemTests-\(UUID().uuidString)")
        let approved = testRoot.appendingPathComponent("approved")
        let nested = approved.appendingPathComponent("Projects/Nested")
        let outside = testRoot.appendingPathComponent("outside")
        try manager.createDirectory(at: nested, withIntermediateDirectories: true)
        try manager.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: testRoot) }

        try Data("top level".utf8).write(to: approved.appendingPathComponent("notes.txt"))
        try Data("# Resume".utf8).write(to: nested.appendingPathComponent("SWE_Resume.MD"))
        try Data("NVIDIA project".utf8).write(to: nested.appendingPathComponent("nViDiA-notes.txt"))
        try Data([0x00, 0x01, 0x02]).write(to: approved.appendingPathComponent("image.bin"))
        try Data(repeating: Character("a").asciiValue!, count: ReadFileTool.maximumContentBytes + 1_024)
            .write(to: approved.appendingPathComponent("large.txt"))
        try Data("outside secret".utf8).write(to: outside.appendingPathComponent("secret.txt"))
        try manager.createSymbolicLink(
            at: approved.appendingPathComponent("escaped-link"),
            withDestinationURL: outside
        )
        for index in 0..<5 {
            try Data("match".utf8).write(to: nested.appendingPathComponent("limit-match-\(index).txt"))
        }
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<25 {
            let fileExtension = index.isMultiple(of: 2) ? "pdf" : "docx"
            let url = nested.appendingPathComponent("latest-resume-\(String(format: "%02d", index)).\(fileExtension)")
            try Data([0x00, UInt8(index)]).write(to: url)
            try manager.setAttributes([.modificationDate: oldDate], ofItemAtPath: url.path)
        }

        let policy = FileAccessPolicy(approvedRoots: [approved], restoreBookmarks: false)
        let listTool = ListDirectoryTool(policy: policy)
        let searchTool = SearchFilesTool(policy: policy)
        let readTool = ReadFileTool(policy: policy)
        let infoTool = GetFileInfoTool(policy: policy)

        let listing = try object(await listTool.execute(arguments: .object(["path": .string(approved.path)])))
        let entries = try array(listing["entries"])
        let entryObjects = try entries.map(object)
        try require(entryObjects.contains { (try? string($0["name"])) == "notes.txt" && (try? string($0["type"])) == "file" }, "list_directory missed a file")
        try require(entryObjects.contains { (try? string($0["name"])) == "Projects" && (try? string($0["type"])) == "directory" }, "list_directory missed a directory")
        try require(!entryObjects.contains { (try? string($0["name"])) == "SWE_Resume.MD" }, "list_directory recursed unexpectedly")
        print("PASS list_directory: files, directories, and non-recursive behavior")

        let resumeSearch = try object(await searchTool.execute(arguments: .object([
            "query": .string("resume"), "directory": .string(approved.path)
        ])))
        let resumeResults = try array(resumeSearch["results"])
        let resumeNames = try resumeResults.map(object).map { try string($0["name"]) }
        try require(resumeNames.contains("SWE_Resume.MD"), "search_files did not find the recursive case-insensitive match")

        let nvidiaSearch = try object(await searchTool.execute(arguments: .object([
            "query": .string("NVIDIA"), "directory": .string(approved.path)
        ])))
        let nvidiaResults = try array(nvidiaSearch["results"])
        try require(nvidiaResults.count == 1, "search_files matching was not case-insensitive")

        let limitedSearch = try object(await searchTool.execute(arguments: .object([
            "query": .string("limit-match"), "directory": .string(approved.path), "maxResults": .number(2)
        ])))
        let limitedResults = try array(limitedSearch["results"])
        try require(limitedResults.count == 2, "search_files did not respect maxResults")
        try require(limitedSearch["limitReached"] == .bool(true), "search_files did not report its limit")

        let traversalOrder = manager.enumerator(
            at: approved,
            includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants]
        )?.compactMap { ($0 as? URL) }
            .filter { $0.lastPathComponent.contains("latest-resume-") } ?? []
        try require(traversalOrder.count == 25, "Newest-after-limit fixture was incomplete")
        guard let newestURL = traversalOrder.last else { throw TestFailure.failed("Missing newest fixture") }
        try require((traversalOrder.firstIndex(of: newestURL) ?? 0) >= 20, "Newest fixture was not after the initial traversal results")
        try manager.setAttributes(
            [.modificationDate: oldDate.addingTimeInterval(10_000)],
            ofItemAtPath: newestURL.path
        )

        let newestSearch = try object(await searchTool.execute(arguments: .object([
            "query": .string("latest-resume"),
            "directory": .string(approved.path),
            "maxResults": .number(3),
            "sortBy": .string("modificationTimeDescending")
        ])))
        let newestResults = try array(newestSearch["results"]).map(object)
        try require(newestResults.count == 3, "Newest search did not apply maxResults after sorting")
        let newestName = try string(newestResults[0]["name"])
        let newestRelativePath = try string(newestResults[0]["relativePath"])
        try require(newestName == newestURL.lastPathComponent, "Newest candidate after the first N traversal results was omitted")
        try require(newestSearch["candidateCount"] == .number(25), "Candidate count was measured after limiting")
        try require(newestSearch["returnedCount"] == .number(3), "Returned count was incorrect")
        try require(newestSearch["sortMode"] == .string("modificationTimeDescending"), "Sort mode was not reported")
        try require(newestResults[0]["relativePath"] != nil && newestResults[0]["sizeBytes"] == .number(2), "Search result metadata was incomplete")
        try require(newestResults[0]["modifiedAt"] != nil && newestResults[0]["fileType"] != nil, "Search result type or timestamp was missing")
        try require(newestRelativePath.hasPrefix("Projects/Nested/"), "Search exposed an unsafe or incorrect relative path")
        try require(!newestRelativePath.hasPrefix("/"), "Search exposed an absolute path")

        let pdfSearch = try object(await searchTool.execute(arguments: .object([
            "query": .string(".pdf"), "directory": .string(approved.path), "maxResults": .number(100)
        ])))
        let docxSearch = try object(await searchTool.execute(arguments: .object([
            "query": .string(".docx"), "directory": .string(approved.path), "maxResults": .number(100)
        ])))
        let pdfResults = try array(pdfSearch["results"])
        let docxResults = try array(docxSearch["results"])
        try require(!pdfResults.isEmpty, "PDF filenames were not searchable")
        try require(!docxResults.isEmpty, "DOCX filenames were not searchable")

        let nameSortedSearch = try object(await searchTool.execute(arguments: .object([
            "query": .string("limit-match"),
            "directory": .string(approved.path),
            "maxResults": .number(5),
            "sortBy": .string("nameDescending")
        ])))
        let nameSorted = try array(nameSortedSearch["results"]).map(object).map { try string($0["name"]) }
        try require(nameSorted == nameSorted.sorted(by: >), "Name sorting was not deterministic")
        try require(nameSortedSearch["limitReached"] == .bool(false), "An exact-limit result set was incorrectly reported as truncated")
        print("PASS search_files: full candidate collection, deterministic sorting, metadata, PDF/DOCX discovery, and post-sort limiting")

        let readResult = try object(await readTool.execute(arguments: .object([
            "path": .string(approved.appendingPathComponent("notes.txt").path)
        ])))
        try require(readResult["content"] == .string("top level"), "read_file returned incorrect content")
        try require(readResult["truncated"] == .bool(false), "read_file incorrectly truncated a small file")

        try await expectError(.unsupportedFileType) {
            _ = try await readTool.execute(arguments: .object([
                "path": .string(approved.appendingPathComponent("image.bin").path)
            ]))
        }
        let largeResult = try object(await readTool.execute(arguments: .object([
            "path": .string(approved.appendingPathComponent("large.txt").path)
        ])))
        try require(largeResult["truncated"] == .bool(true), "read_file did not truncate an oversized file")
        try require(largeResult["returnedBytes"] == .number(Double(ReadFileTool.maximumContentBytes)), "read_file returned too many bytes")
        print("PASS read_file: supported text, binary rejection, and bounded truncation")

        let info = try object(await infoTool.execute(arguments: .object([
            "path": .string(approved.appendingPathComponent("notes.txt").path)
        ])))
        try require(info["name"] == .string("notes.txt"), "get_file_info returned the wrong name")
        try require(info["type"] == .string("file"), "get_file_info returned the wrong type")
        try require(info["sizeBytes"] == .number(9), "get_file_info returned the wrong size")
        try await expectError(.pathDoesNotExist) {
            _ = try await infoTool.execute(arguments: .object([
                "path": .string(approved.appendingPathComponent("missing.txt").path)
            ]))
        }
        print("PASS get_file_info: metadata and missing path")

        let traversalPaths = [
            approved.appendingPathComponent("../outside/secret.txt").path,
            approved.appendingPathComponent("../../").path,
            approved.appendingPathComponent("Projects/../../outside/secret.txt").path,
            approved.appendingPathComponent("escaped-link/secret.txt").path
        ]
        for path in traversalPaths {
            try await expectError(.accessDenied) { _ = try policy.validate(path) }
        }
        print("PASS security: traversal and symbolic-link escapes denied")

        let defaultsSuite = "PersonalAI.FileAccessPolicyTests.\(UUID().uuidString)"
        guard let testDefaults = UserDefaults(suiteName: defaultsSuite) else {
            throw TestFailure.failed("Could not create isolated UserDefaults suite")
        }
        defer { testDefaults.removePersistentDomain(forName: defaultsSuite) }
        let bookmarkKey = "testBookmarks"
        let secondApproved = testRoot.appendingPathComponent("second-approved")
        try manager.createDirectory(at: secondApproved, withIntermediateDirectories: true)

        var bookmarkPolicy: FileAccessPolicy? = FileAccessPolicy(
            approvedRoots: [],
            restoreBookmarks: false,
            defaults: testDefaults,
            bookmarkDefaultsKey: bookmarkKey
        )
        try bookmarkPolicy?.approveUserSelectedDirectory(approved)
        try bookmarkPolicy?.approveUserSelectedDirectory(secondApproved)
        try require(bookmarkPolicy?.userApprovedDirectories.count == 2, "Multiple selected folders were not retained")
        bookmarkPolicy = nil

        var restoredPolicy: FileAccessPolicy? = FileAccessPolicy(
            approvedRoots: [],
            restoreBookmarks: true,
            defaults: testDefaults,
            bookmarkDefaultsKey: bookmarkKey
        )
        try require(restoredPolicy?.userApprovedDirectories.count == 2, "Bookmarks were not restored")
        try restoredPolicy?.removeUserSelectedDirectory(path: approved.path)
        try require(restoredPolicy?.userApprovedDirectories.count == 1, "Removed folder remained configured")
        try await expectError(.accessDenied) {
            _ = try restoredPolicy?.validate(approved.appendingPathComponent("notes.txt").path)
        }
        restoredPolicy = nil

        let afterRemovalPolicy = FileAccessPolicy(
            approvedRoots: [],
            restoreBookmarks: true,
            defaults: testDefaults,
            bookmarkDefaultsKey: bookmarkKey
        )
        try require(afterRemovalPolicy.userApprovedDirectories.count == 1, "Removed bookmark returned after relaunch")
        try require(afterRemovalPolicy.userApprovedDirectories[0].path == secondApproved.path, "Wrong folder survived bookmark removal")

        testDefaults.set([Data([0x00, 0x01, 0x02])], forKey: "invalidBookmarks")
        let invalidBookmarkPolicy = FileAccessPolicy(
            approvedRoots: [],
            restoreBookmarks: true,
            defaults: testDefaults,
            bookmarkDefaultsKey: "invalidBookmarks"
        )
        try require(invalidBookmarkPolicy.userApprovedDirectories.isEmpty, "Invalid bookmark silently granted access")
        print("PASS permissions: multiple bookmarks, restoration, revocation, and invalid bookmark rejection")
        print("ALL FILESYSTEM TOOL TESTS PASSED")
    }
}
