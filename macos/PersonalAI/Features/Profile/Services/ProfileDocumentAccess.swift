import Foundation
import os
import UniformTypeIdentifiers

enum ProfileDocumentAccessError: LocalizedError, Equatable {
    case selectionInvalid
    case unsupportedFileType
    case securityScopeFailed
    case bookmarkCreationFailed
    case bookmarkPersistenceFailed

    var errorDescription: String? {
        switch self {
        case .selectionInvalid: "The selected document is not a readable file."
        case .unsupportedFileType: "Select a PDF, Word, rich text, or plain text document."
        case .securityScopeFailed: "The selected document permission could not be established."
        case .bookmarkCreationFailed: "The selected document permission could not be saved."
        case .bookmarkPersistenceFailed: "The selected document permission could not be persisted."
        }
    }
}

struct ProfileDocumentAssociation {
    let url: URL
    fileprivate let previousBookmark: Data?
}

/// Persists security-scoped bookmarks separately from Profile metadata. SQLite
/// remains authoritative for the association; bookmarks only restore sandbox access.
final class ProfileDocumentAccess {
    static let shared = ProfileDocumentAccess()
    static let allowedContentTypes: [UTType] = [.pdf, .plainText, .rtf] +
        ["doc", "docx"].compactMap { UTType(filenameExtension: $0) }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.personalai.app",
        category: "PersonalAI.ProfileDocuments"
    )

    private let defaults: UserDefaults
    private let defaultsKey: String

    init(defaults: UserDefaults = .standard, defaultsKey: String = "profileDocumentBookmarks") {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
    }

    func associate(_ url: URL, with documentID: String, documentType: String) throws -> ProfileDocumentAssociation {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: url.path) else {
            logFailure(documentType: documentType, stage: "selection_validation")
            throw ProfileDocumentAccessError.selectionInvalid
        }
        guard Self.isAllowedDocument(url) else {
            logFailure(documentType: documentType, stage: "file_type_validation")
            throw ProfileDocumentAccessError.unsupportedFileType
        }

        let started = url.startAccessingSecurityScopedResource()
        // URLs returned by NSOpenPanel may already be directly accessible in
        // non-sandboxed tests, where this API legitimately returns false.
        #if !DEBUG
        guard started else {
            logFailure(documentType: documentType, stage: "security_scope")
            throw ProfileDocumentAccessError.securityScopeFailed
        }
        #endif
        defer { if started { url.stopAccessingSecurityScopedResource() } }

        let bookmark: Data
        do {
            bookmark = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: [.contentTypeKey, .isRegularFileKey],
                relativeTo: nil
            )
        } catch {
            logFailure(documentType: documentType, stage: "bookmark_creation")
            throw ProfileDocumentAccessError.bookmarkCreationFailed
        }

        let previousBookmark = storedBookmarks[documentID]
        var bookmarks = storedBookmarks
        bookmarks[documentID] = bookmark
        defaults.set(bookmarks, forKey: defaultsKey)
        guard storedBookmarks[documentID] == bookmark else {
            bookmarks[documentID] = previousBookmark
            defaults.set(bookmarks, forKey: defaultsKey)
            logFailure(documentType: documentType, stage: "bookmark_persistence")
            throw ProfileDocumentAccessError.bookmarkPersistenceFailed
        }
        logSuccess(documentType: documentType)
        return ProfileDocumentAssociation(url: url.standardizedFileURL, previousBookmark: previousBookmark)
    }

    func rollback(_ association: ProfileDocumentAssociation, for documentID: String) {
        var bookmarks = storedBookmarks
        bookmarks[documentID] = association.previousBookmark
        defaults.set(bookmarks, forKey: defaultsKey)
    }

    func removeAssociation(for documentID: String) {
        var bookmarks = storedBookmarks
        bookmarks.removeValue(forKey: documentID)
        defaults.set(bookmarks, forKey: defaultsKey)
    }

    func resolvedURL(for documentID: String) -> URL? {
        guard let bookmark = storedBookmarks[documentID] else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale, let refreshed = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) {
            var bookmarks = storedBookmarks
            bookmarks[documentID] = refreshed
            defaults.set(bookmarks, forKey: defaultsKey)
        }
        return url
    }

    private var storedBookmarks: [String: Data] {
        defaults.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
    }

    private static func isAllowedDocument(_ url: URL) -> Bool {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           allowedContentTypes.contains(where: { type.conforms(to: $0) }) {
            return true
        }
        return ["pdf", "doc", "docx", "rtf", "txt"].contains(url.pathExtension.lowercased())
    }

    private func logFailure(documentType: String, stage: String) {
        #if DEBUG
        Self.logger.error("Profile document association failed documentType=\(documentType, privacy: .public) operation=associate stage=\(stage, privacy: .public) success=false")
        #endif
    }

    private func logSuccess(documentType: String) {
        #if DEBUG
        Self.logger.notice("Profile document association documentType=\(documentType, privacy: .public) operation=associate stage=bookmark_persistence success=true")
        #endif
    }
}
