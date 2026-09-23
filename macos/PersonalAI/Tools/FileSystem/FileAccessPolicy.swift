import Foundation

struct ApprovedDirectory: Identifiable, Equatable, Sendable {
    let path: String

    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

extension Notification.Name {
    static let fileAccessPolicyDidChange = Notification.Name("FileAccessPolicyDidChange")
}

enum FileAccessError: LocalizedError, Equatable {
    case accessDenied
    case pathDoesNotExist
    case expectedDirectory
    case expectedFile
    case permissionDenied
    case unsupportedFileType
    case malformedArguments(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Access denied: path is outside approved directories."
        case .pathDoesNotExist:
            "The requested filesystem path does not exist."
        case .expectedDirectory:
            "The requested path is not a directory."
        case .expectedFile:
            "The requested path is not a file."
        case .permissionDenied:
            "Permission denied. Select the directory in Settings to grant read-only access."
        case .unsupportedFileType:
            "Unsupported file type for read_file."
        case .malformedArguments(let message):
            "Invalid tool arguments: \(message)"
        case .unreadable(let message):
            "Unable to read the requested path: \(message)"
        }
    }
}

/// Enforces the application's allowlist independently from macOS App Sandbox.
/// All roots and requested paths are canonicalized before component-based containment checks.
final class FileAccessPolicy: @unchecked Sendable {
    static let shared = FileAccessPolicy()

    private struct SecurityScopedRoot {
        let canonicalURL: URL
        let accessURL: URL
        let bookmark: Data
        let isAccessing: Bool
    }

    private let lock = NSLock()
    private let implicitRoots: [URL]
    private let defaults: UserDefaults
    private let bookmarkDefaultsKey: String
    private var userSelectedRoots: [SecurityScopedRoot] = []

    init(
        approvedRoots: [URL]? = nil,
        restoreBookmarks: Bool = true,
        defaults: UserDefaults = .standard,
        bookmarkDefaultsKey: String = "approvedDirectoryBookmarks"
    ) {
        // Explicit roots are an injection point for deterministic tests. Production uses
        // only user-selected, bookmark-backed roots restored below.
        self.implicitRoots = Self.uniqueCanonicalURLs(approvedRoots ?? [])
        self.defaults = defaults
        self.bookmarkDefaultsKey = bookmarkDefaultsKey
        if restoreBookmarks { restoreSecurityScopedBookmarks() }
    }

    deinit {
        let roots = lock.withLock { userSelectedRoots }
        roots.filter(\.isAccessing).forEach { $0.accessURL.stopAccessingSecurityScopedResource() }
    }

    var approvedRootPaths: [String] {
        lock.withLock {
            Self.uniqueCanonicalURLs(implicitRoots + userSelectedRoots.map(\.canonicalURL))
                .map(\.path)
                .sorted()
        }
    }

    var userApprovedDirectories: [ApprovedDirectory] {
        lock.withLock {
            userSelectedRoots
                .map { ApprovedDirectory(path: $0.canonicalURL.path) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    @discardableResult
    func approveUserSelectedDirectory(_ url: URL) throws -> URL {
        let canonical = try canonicalURL(for: url.path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FileAccessError.expectedDirectory
        }

        // The URL returned by NSOpenPanel owns the sandbox extension. Keep that exact URL
        // alive while using a canonical URL separately for policy comparisons.
        let started = url.startAccessingSecurityScopedResource()
        let bookmark: Data
        do {
            bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            if started { url.stopAccessingSecurityScopedResource() }
            throw FileAccessError.unreadable(error.localizedDescription)
        }

        let wasAdded = lock.withLock { () -> Bool in
            guard !userSelectedRoots.contains(where: { $0.canonicalURL.path == canonical.path }) else {
                return false
            }
            userSelectedRoots.append(SecurityScopedRoot(
                canonicalURL: canonical,
                accessURL: url,
                bookmark: bookmark,
                isAccessing: started
            ))
            persistBookmarksLocked()
            return true
        }
        if !wasAdded, started { url.stopAccessingSecurityScopedResource() }
        if wasAdded { notifyChange() }
        return canonical
    }

    func removeUserSelectedDirectory(path: String) throws {
        let canonical = try canonicalURL(for: path)
        let removed = lock.withLock { () -> SecurityScopedRoot? in
            guard let index = userSelectedRoots.firstIndex(where: { $0.canonicalURL.path == canonical.path }) else {
                return nil
            }
            let removed = userSelectedRoots.remove(at: index)
            persistBookmarksLocked()
            return removed
        }
        guard let removed else { return }
        if removed.isAccessing { removed.accessURL.stopAccessingSecurityScopedResource() }
        notifyChange()
    }

    func validate(_ path: String, mustExist: Bool = true) throws -> URL {
        let candidate = try canonicalURL(for: path)
        let roots = lock.withLock { implicitRoots + userSelectedRoots.map(\.canonicalURL) }
        guard roots.contains(where: { Self.contains(candidate, within: $0) }) else {
            throw FileAccessError.accessDenied
        }
        if mustExist, !FileManager.default.fileExists(atPath: candidate.path) {
            throw FileAccessError.pathDoesNotExist
        }
        return candidate
    }

    private func canonicalURL(for path: String) throws -> URL {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FileAccessError.malformedArguments("path must not be empty")
        }
        let expanded = (path as NSString).expandingTildeInPath
        let absolute: URL
        if expanded.hasPrefix("/") {
            absolute = URL(fileURLWithPath: expanded)
        } else {
            absolute = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(expanded)
        }
        let canonical = absolute.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        return canonical
    }

    private func restoreSecurityScopedBookmarks() {
        let bookmarks = defaults.array(forKey: bookmarkDefaultsKey) as? [Data] ?? []
        var restored: [SecurityScopedRoot] = []
        for bookmark in bookmarks {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { continue }
            let started = url.startAccessingSecurityScopedResource()
            let canonical = url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                if started { url.stopAccessingSecurityScopedResource() }
                continue
            }

            let currentBookmark: Data
            if stale {
                guard let refreshed = try? url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) else {
                    if started { url.stopAccessingSecurityScopedResource() }
                    continue
                }
                currentBookmark = refreshed
            } else {
                currentBookmark = bookmark
            }

            guard !restored.contains(where: { $0.canonicalURL.path == canonical.path }) else {
                if started { url.stopAccessingSecurityScopedResource() }
                continue
            }
            restored.append(SecurityScopedRoot(
                canonicalURL: canonical,
                accessURL: url,
                bookmark: currentBookmark,
                isAccessing: started
            ))
        }
        lock.withLock {
            userSelectedRoots = restored
            persistBookmarksLocked()
        }
    }

    private func persistBookmarksLocked() {
        defaults.set(userSelectedRoots.map(\.bookmark), forKey: bookmarkDefaultsKey)
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .fileAccessPolicyDidChange, object: self)
    }

    private static func uniqueCanonicalURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.compactMap {
            let canonical = $0.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
            return seen.insert(canonical.path).inserted ? canonical : nil
        }
    }

    private static func contains(_ candidate: URL, within root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        return candidateComponents.count >= rootComponents.count &&
            Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
