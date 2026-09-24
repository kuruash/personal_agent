import Foundation
import UniformTypeIdentifiers

struct ChatAttachment: Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let contentTypeIdentifier: String?
    let byteSize: Int64?
    fileprivate let bookmarkData: Data

    init(
        id: UUID = UUID(),
        displayName: String,
        contentTypeIdentifier: String?,
        byteSize: Int64?,
        bookmarkData: Data
    ) {
        self.id = id
        self.displayName = displayName
        self.contentTypeIdentifier = contentTypeIdentifier
        self.byteSize = byteSize
        self.bookmarkData = bookmarkData
    }

    var systemImageName: String {
        guard let contentTypeIdentifier,
              let type = UTType(contentTypeIdentifier) else { return "doc.fill" }
        if type.conforms(to: .image) { return "photo.fill" }
        if type.conforms(to: .pdf) { return "doc.richtext.fill" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .movie) { return "film.fill" }
        if type.conforms(to: .archive) { return "archivebox.fill" }
        return "doc.fill"
    }
}

enum ChatAttachmentError: LocalizedError, Equatable {
    case invalidSelection
    case permissionFailed
    case bookmarkCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidSelection:
            "The selected item is not a readable file."
        case .permissionFailed:
            "Personal AI could not access the selected file."
        case .bookmarkCreationFailed:
            "Personal AI could not retain permission for the selected file."
        }
    }
}

enum ChatAttachmentAccess {
    static func makeAttachment(from url: URL) throws -> ChatAttachment {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .isRegularFileKey, .isReadableKey, .contentTypeKey, .fileSizeKey
            ])
        } catch {
            throw ChatAttachmentError.invalidSelection
        }
        guard values.isRegularFile == true, values.isReadable != false else {
            throw ChatAttachmentError.invalidSelection
        }

        let started = url.startAccessingSecurityScopedResource()
        #if !DEBUG
        guard started else { throw ChatAttachmentError.permissionFailed }
        #endif
        defer { if started { url.stopAccessingSecurityScopedResource() } }

        let bookmark: Data
        do {
            bookmark = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: [.contentTypeKey, .fileSizeKey],
                relativeTo: nil
            )
        } catch {
            throw ChatAttachmentError.bookmarkCreationFailed
        }

        return ChatAttachment(
            displayName: url.lastPathComponent,
            contentTypeIdentifier: values.contentType?.identifier,
            byteSize: values.fileSize.map(Int64.init),
            bookmarkData: bookmark
        )
    }
}
