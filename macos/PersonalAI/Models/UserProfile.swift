import Foundation

struct UserProfile: Equatable, Sendable {
    var fullName: String?
    var preferredName: String?
    var location: String?
    var email: String?
    var phone: String?
    let createdAt: Date
    var updatedAt: Date
}

struct ProfileLink: Identifiable, Equatable, Sendable {
    let id: UUID
    var label: String
    var url: String
    let createdAt: Date
    var updatedAt: Date
}
