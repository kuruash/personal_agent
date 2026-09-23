import Foundation

struct DocumentMetadata: Identifiable, Equatable, Sendable {
    let id: String
    var type: String
    var name: String
    var filePath: String?
    var mimeType: String?
    var isPrimary: Bool
    let createdAt: Date
    var updatedAt: Date
}
