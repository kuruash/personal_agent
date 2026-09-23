import Foundation

enum ProfileSection: String, CaseIterable, Codable, Sendable {
    case identity, contact, address, links, education, experience, skills, projects
    case certifications
    case careerPreferences = "career_preferences"
    case workAuthorization = "work_authorization"
    case applicationAnswers = "application_answers"
    case documents
}

struct PersonalProfile: Codable, Equatable, Sendable {
    var identity: ProfileIdentity
    var contact: ProfileContact
    var address: ProfileAddress?
    var links: [ProfileLinkRecord]
    var education: [EducationRecord]
    var experience: [ExperienceRecord]
    var skills: [SkillCategory]
    var projects: [ProjectRecord]
    var certifications: [CertificationRecord]
    var careerPreferences: CareerPreferences
    var workAuthorization: WorkAuthorization
    var applicationAnswers: ApplicationAnswers
    var documents: [ProfileDocument]
}

struct ProfileIdentity: Codable, Equatable, Sendable {
    var fullName: String
    var firstName: String
    var lastName: String
    var preferredName: String
    var legalName: String
}

struct ProfileContact: Codable, Equatable, Sendable {
    var primaryEmail: String
    var alternateEmail: String?
    var primaryPhone: String
}

struct ProfileAddress: Codable, Equatable, Sendable {
    var street: String
    var city: String
    var state: String
    var postalCode: String
    var country: String
}

struct ProfileLinkRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var url: String
}

struct EducationRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var institution: String
    var degree: String
    var major: String
    var startDate: String
    var graduationDate: String
    var gpa: Double?
    var coursework: [String]
    var activities: [String]
    var achievements: [String]
}

struct ExperienceRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var company: String
    var title: String
    var employmentType: String
    var location: String
    var startDate: String
    var endDate: String?
    var isCurrent: Bool
    var achievements: [String]
    var technologies: [String]
}

struct SkillCategory: Codable, Equatable, Sendable {
    var category: String
    var skills: [String]
}

struct ProjectRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var technologies: [String]
    var repositoryURL: String?
    var description: String?
    var highlights: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, technologies, description, highlights
        case repositoryURL = "repositoryUrl"
    }
}

struct CertificationRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String?
    var issuer: String?
    var type: String?
    var issueDate: String?
    var expirationDate: String?
    var credentialID: String?
    var credentialURL: String?
    var unresolved: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, issuer, type, unresolved
        case issueDate, expirationDate
        case credentialID = "credentialId"
        case credentialURL = "credentialUrl"
    }
}

struct CareerPreferences: Codable, Equatable, Sendable {
    var targetRoles: [String]
    var preferredLocations: [String]
    var remote: Bool
    var hybrid: Bool
    var onsite: Bool
    var willingToRelocate: Bool
    var preferredIndustries: [String]
    var earliestStartDate: String?
}

struct WorkAuthorization: Codable, Equatable, Sendable {
    var country: String
    var currentStatus: String?
    var authorizationType: String?
    var authorizationStartDate: String?
    var authorizationExpirationDate: String?
    var currentlyRequiredSponsorship: Bool
    var futureRequiredSponsorship: Bool
    var futureSponsorshipType: String?
}

struct ApplicationAnswers: Codable, Equatable, Sendable {
    var authorizedToWorkInUS: Bool
    var requiresCurrentSponsorship: Bool
    var requiresFutureSponsorship: Bool
    var willingToRelocate: Bool
    var willingToWorkOnsite: Bool
    var willingToWorkHybrid: Bool
    var willingToWorkRemote: Bool

    enum CodingKeys: String, CodingKey {
        case authorizedToWorkInUS = "authorizedToWorkInUs"
        case requiresCurrentSponsorship, requiresFutureSponsorship
        case willingToRelocate, willingToWorkOnsite, willingToWorkHybrid, willingToWorkRemote
    }
}

struct ProfileDocument: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var type: String
    var label: String
    var filename: String?
    var path: String?
    var preferred: Bool
    var lastUpdated: String?
}

struct ProfileSearchResult: Codable, Equatable, Sendable {
    var section: ProfileSection
    var recordID: String?
    var field: String
    var value: String
}
