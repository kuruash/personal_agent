import Foundation
import os

enum ProfileImportError: LocalizedError {
    case malformedSeed
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .malformedSeed: "The local profile seed is not valid JSON for the supported profile schema."
        case .validationFailed(let detail): "The local profile seed is invalid: \(detail)"
        }
    }
}

struct ProfileImportSummary: Equatable, Sendable {
    let educationCount: Int
    let experienceCount: Int
    let projectCount: Int
    let certificationCount: Int
}

struct ProfileImportService {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.personalai.app",
        category: "PersonalAI.ProfileImport"
    )

    let repository: ProfileRepository

    func importSeed(at url: URL) throws -> ProfileImportSummary {
        let profile: PersonalProfile
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            profile = try decoder.decode(PersonalProfile.self, from: data)
        } catch let error as ProfileImportError {
            throw error
        } catch {
            throw ProfileImportError.malformedSeed
        }

        try validate(profile)
        try repository.importProfile(profile)
        let summary = ProfileImportSummary(
            educationCount: profile.education.count,
            experienceCount: profile.experience.count,
            projectCount: profile.projects.count,
            certificationCount: profile.certifications.count
        )
        #if DEBUG
        Self.logger.notice("Profile import succeeded")
        Self.logger.notice("Education records: \(summary.educationCount, privacy: .public)")
        Self.logger.notice("Experience records: \(summary.experienceCount, privacy: .public)")
        Self.logger.notice("Projects: \(summary.projectCount, privacy: .public)")
        #endif
        return summary
    }

    private func validate(_ profile: PersonalProfile) throws {
        let required = [
            profile.identity.fullName, profile.identity.firstName, profile.identity.lastName,
            profile.identity.preferredName, profile.identity.legalName,
            profile.contact.primaryEmail, profile.contact.primaryPhone
        ]
        guard required.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ProfileImportError.validationFailed("required identity or contact fields are empty")
        }
        let ids = profile.links.map(\.id) + profile.education.map(\.id) + profile.experience.map(\.id) +
            profile.projects.map(\.id) + profile.certifications.map(\.id) + profile.documents.map(\.id)
        guard ids.allSatisfy({ !$0.isEmpty }) else {
            throw ProfileImportError.validationFailed("record IDs must not be empty")
        }
        guard Set(ids).count == ids.count else {
            throw ProfileImportError.validationFailed("record IDs must be unique across the profile")
        }
    }
}
