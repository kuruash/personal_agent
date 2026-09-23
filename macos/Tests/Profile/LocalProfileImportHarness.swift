import Foundation

@main
private struct LocalProfileImportHarness {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw ProfileImportError.validationFailed("expected seed and database paths")
        }
        let seedURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let databaseURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let database = try DatabaseManager(databaseURL: databaseURL)
        let summary = try ProfileImportService(
            repository: ProfileRepository(database: database)
        ).importSeed(at: seedURL)
        print("Profile import succeeded")
        print("Education records: \(summary.educationCount)")
        print("Experience records: \(summary.experienceCount)")
        print("Projects: \(summary.projectCount)")
        print("Certifications: \(summary.certificationCount)")
    }
}
