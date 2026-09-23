import Foundation

final class ProfileStore: @unchecked Sendable {
    private let repository: ProfileRepository

    init(repository: ProfileRepository) {
        self.repository = repository
    }

    convenience init(database: DatabaseManager) {
        self.init(repository: ProfileRepository(database: database))
    }

    func loadProfile() throws -> PersonalProfile? {
        try repository.loadPersonalProfile()
    }

    func availableSections() throws -> [ProfileSection] {
        guard let profile = try loadProfile() else { return [] }
        return ProfileSection.allCases.filter { section in
            switch section {
            case .address: return profile.address != nil
            case .links: return !profile.links.isEmpty
            case .education: return !profile.education.isEmpty
            case .experience: return !profile.experience.isEmpty
            case .skills: return !profile.skills.isEmpty
            case .projects: return !profile.projects.isEmpty
            case .certifications: return !profile.certifications.isEmpty
            case .documents: return !profile.documents.isEmpty
            default: return true
            }
        }
    }

    func section(_ section: ProfileSection) throws -> JSONValue {
        guard let profile = try loadProfile() else {
            return .object(["section": .string(section.rawValue), "available": .bool(false)])
        }
        let value: any Encodable = switch section {
        case .identity: profile.identity
        case .contact: profile.contact
        case .address: profile.address
        case .links: profile.links
        case .education: profile.education
        case .experience: profile.experience
        case .skills: profile.skills
        case .projects: profile.projects
        case .certifications: profile.certifications
        case .careerPreferences: profile.careerPreferences
        case .workAuthorization: profile.workAuthorization
        case .applicationAnswers: profile.applicationAnswers
        case .documents: profile.documents
        }
        return try Self.jsonValue(value)
    }

    func search(_ query: String, limit: Int = 20) throws -> [ProfileSearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, let profile = try loadProfile() else { return [] }
        var results: [ProfileSearchResult] = []
        func add(_ section: ProfileSection, _ recordID: String?, _ field: String, _ values: [String]) {
            for value in values where value.localizedCaseInsensitiveContains(needle) && results.count < limit {
                results.append(ProfileSearchResult(section: section, recordID: recordID, field: field, value: value))
            }
        }

        add(.identity, nil, "identity", [profile.identity.fullName, profile.identity.firstName, profile.identity.lastName, profile.identity.preferredName, profile.identity.legalName])
        add(.contact, nil, "contact", [profile.contact.primaryEmail, profile.contact.alternateEmail, profile.contact.primaryPhone].compactMap { $0 })
        if let a = profile.address { add(.address, nil, "address", [a.street, a.city, a.state, a.postalCode, a.country]) }
        for r in profile.links { add(.links, r.id, "link", [r.label, r.url]) }
        for r in profile.education {
            add(.education, r.id, "education", [r.institution, r.degree, r.major, r.startDate, r.graduationDate] + r.coursework + r.activities + r.achievements)
        }
        for r in profile.experience {
            add(.experience, r.id, "experience", [r.company, r.title, r.employmentType, r.location] + r.technologies + r.achievements)
        }
        for r in profile.skills { add(.skills, r.category, "skills", [r.category] + r.skills) }
        for r in profile.projects { add(.projects, r.id, "project", [r.name, r.repositoryURL, r.description].compactMap { $0 } + r.technologies + r.highlights) }
        for r in profile.certifications { add(.certifications, r.id, "credential", [r.name, r.issuer, r.type, r.credentialID, r.credentialURL].compactMap { $0 }) }
        add(.careerPreferences, nil, "preferences", profile.careerPreferences.targetRoles + profile.careerPreferences.preferredLocations + profile.careerPreferences.preferredIndustries)
        add(.workAuthorization, nil, "authorization", [profile.workAuthorization.country, profile.workAuthorization.currentStatus, profile.workAuthorization.authorizationType, profile.workAuthorization.futureSponsorshipType].compactMap { $0 })
        for r in profile.documents { add(.documents, r.id, "document", [r.type, r.label, r.filename].compactMap { $0 }) }
        return Array(results.prefix(limit))
    }

    private static func jsonValue(_ value: any Encodable) throws -> JSONValue {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(AnyEncodable(value))
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

private struct AnyEncodable: Encodable {
    let encodeBlock: (Encoder) throws -> Void
    init(_ value: any Encodable) { encodeBlock = value.encode }
    func encode(to encoder: Encoder) throws { try encodeBlock(encoder) }
}
