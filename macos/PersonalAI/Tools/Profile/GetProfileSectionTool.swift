import Foundation

struct GetProfileSectionTool: AgentTool {
    let name = "get_profile_section"
    let description = "Retrieves one explicitly named section of the local structured Personal Profile. Valid sections are identity, contact, address, links, education, experience, skills, projects, certifications, career_preferences, work_authorization, application_answers, and documents."
    let parameterSchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "section": .object([
                "type": .string("string"),
                "enum": .array(ProfileSection.allCases.map { .string($0.rawValue) })
            ])
        ]),
        "required": .array([.string("section")]),
        "additionalProperties": .bool(false)
    ])
    let store: ProfileStore

    func execute(arguments: JSONValue) async throws -> JSONValue {
        let object = try ProfileToolSupport.objectArguments(arguments)
        let raw = try ProfileToolSupport.string("section", in: object)
        guard let section = ProfileSection(rawValue: raw) else {
            throw AgentToolError.invalidArguments("Unknown profile section.")
        }
        return .object([
            "section": .string(section.rawValue),
            "data": try store.section(section)
        ])
    }
}
