import Foundation

private enum ProfileTestError: Error { case failed(String) }
private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw ProfileTestError.failed(message) }
}

private actor ProfileToolCallingClient: NebiusServing {
    private var requestCount = 0

    func fetchModels() async throws -> [AvailableModel] {
        [AvailableModel(id: "nvidia/Nemotron-Profile-Test")]
    }

    func createChatCompletion(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        requestCount += 1
        if requestCount == 1 {
            guard request.tools?.contains(where: { $0.function.name == "get_profile_section" }) == true else {
                throw ProfileTestError.failed("Profile tools were not exposed to Nemotron")
            }
            return ChatCompletionResponse(choices: [ChatChoice(
                message: ChatMessage(role: "assistant", toolCalls: [ToolCall(
                    id: "profile-call-1", type: "function",
                    function: ToolCallFunction(name: "get_profile_section", arguments: "{\"section\":\"education\"}")
                )]), finishReason: "tool_calls"
            )])
        }
        guard let toolMessage = request.messages.last,
              toolMessage.role == "tool", toolMessage.name == "get_profile_section",
              toolMessage.toolCallID == "profile-call-1",
              toolMessage.content?.contains("Example University") == true else {
            throw ProfileTestError.failed("AgentRuntime did not return structured profile data to Nemotron")
        }
        return ChatCompletionResponse(choices: [ChatChoice(
            message: ChatMessage(role: "assistant", content: "The profile education section was retrieved."),
            finishReason: "stop"
        )])
    }
}

@main
private struct ProfileHarness {
    static func main() async throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("PersonalAI-ProfileTests-\(UUID().uuidString)")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }

        let database = try DatabaseManager(databaseURL: directory.appendingPathComponent("profile.sqlite"))
        let repository = ProfileRepository(database: database)
        let conversationRepository = ConversationRepository(database: database)
        let documentRepository = DocumentRepository(database: database)
        let conversation = Conversation(
            title: "Preserved chat",
            messages: [ConversationMessage(role: .user, content: "Keep this conversation")]
        )
        try conversationRepository.save(conversation)
        let existingDocumentDate = Date(timeIntervalSince1970: 1_700_000_000)
        try documentRepository.saveDocumentMetadata(DocumentMetadata(
            id: "example_resume", type: "resume", name: "Existing Resume",
            filePath: "/approved/example-resume.pdf", mimeType: "application/pdf",
            isPrimary: true, createdAt: existingDocumentDate, updatedAt: existingDocumentDate
        ))

        let fixture = fictionalProfile()
        let seedURL = directory.appendingPathComponent("profile.json")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        try encoder.encode(fixture).write(to: seedURL, options: .atomic)
        let importer = ProfileImportService(repository: repository)
        let summary = try importer.importSeed(at: seedURL)
        try require(summary.experienceCount == 2 && summary.projectCount == 2, "Import summary was incorrect")
        let preservedConversation = try conversationRepository.loadConversation(id: conversation.id)
        try require(preservedConversation != nil, "Profile import modified conversations")

        _ = try importer.importSeed(at: seedURL)
        let counts = try database.read { connection in
            try ["profile_experience", "profile_education", "profile_projects", "profile_certifications", "profile_links"].map {
                try connection.query("SELECT COUNT(*) AS count FROM \($0);").first?.integer("count") ?? -1
            }
        }
        try require(counts == [2, 1, 2, 1, 1], "Repeated import created duplicates")
        print("PASS import: valid seed, stable IDs, idempotency, and conversation isolation")

        let loaded = try repository.loadPersonalProfile()
        try require(loaded?.identity == fixture.identity, "Identity retrieval failed")
        try require(loaded?.contact == fixture.contact, "Contact retrieval failed")
        try require(loaded?.address == fixture.address, "Address retrieval failed")
        try require(loaded?.links == fixture.links, "Links retrieval failed")
        try require(loaded?.education == fixture.education, "Education retrieval failed")
        try require(loaded?.experience == fixture.experience, "Experience retrieval failed")
        try require(loaded?.skills == fixture.skills, "Skills retrieval failed")
        try require(loaded?.projects == fixture.projects, "Projects retrieval failed")
        try require(loaded?.certifications == fixture.certifications, "Certifications retrieval failed")
        try require(loaded?.careerPreferences == fixture.careerPreferences, "Career preference retrieval failed")
        try require(loaded?.workAuthorization == fixture.workAuthorization, "Work authorization retrieval failed")
        try require(loaded?.applicationAnswers == fixture.applicationAnswers, "Application answer retrieval failed")
        try require(loaded?.documents.count == fixture.documents.count, "Document metadata retrieval failed")
        try require(loaded?.documents.first?.path == "/approved/example-resume.pdf", "Seed import overwrote an existing document path")
        print("PASS repository: every canonical section round-tripped")

        let store = ProfileStore(repository: repository)
        for query in ["AWS", "Kubernetes", "Python", "Go", "RAG"] {
            let matches = try store.search(query)
            try require(!matches.isEmpty, "Search returned no result for \(query)")
        }
        let goMatches = try store.search("Go")
        try require(goMatches.contains { $0.section == .projects && $0.recordID == "example_go_service" }, "Go project provenance was missing")
        print("PASS search: deterministic case-insensitive matches include provenance")

        let indexTool = GetProfileIndexTool(store: store)
        let indexResult = try await indexTool.execute(arguments: .object([:]))
        guard case .object(let indexObject) = indexResult,
              case .array(let sections) = indexObject["available_sections"] else {
            throw ProfileTestError.failed("Profile index result was malformed")
        }
        try require(sections.count == ProfileSection.allCases.count, "Profile index omitted a populated section")
        let sectionTool = GetProfileSectionTool(store: store)
        let sectionResult = try await sectionTool.execute(arguments: .object(["section": .string("education")]))
        guard case .object(let sectionObject) = sectionResult, sectionObject["section"] == .string("education") else {
            throw ProfileTestError.failed("Profile section tool result was malformed")
        }
        do {
            _ = try await sectionTool.execute(arguments: .object(["section": .string("conversations; DROP TABLE profile_identity")]))
            throw ProfileTestError.failed("Invalid profile section was accepted")
        } catch is AgentToolError { }
        let searchResult = try await SearchProfileTool(store: store).execute(arguments: .object(["query": .string("Kubernetes")]))
        guard case .object(let searchObject) = searchResult,
              case .array(let toolResults) = searchObject["results"], !toolResults.isEmpty else {
            throw ProfileTestError.failed("Profile search tool returned no structured results")
        }
        print("PASS tools: index, validated section retrieval, search, and SQL-name rejection")

        let runtime = AgentRuntime(
            client: ProfileToolCallingClient(),
            tools: [indexTool, sectionTool, SearchProfileTool(store: store)]
        )
        let runtimeAnswer = try await runtime.send(userMessage: "Where did I study?")
        try require(runtimeAnswer == "The profile education section was retrieved.", "Profile tool loop did not complete")
        print("PASS agent integration: Nemotron requested a profile tool and received the local result")

        let privateArguments: JSONValue = .object(["query": .string("private-profile-value")])
        let traceInput = TracingPolicy.toolInputs(name: "search_profile", arguments: privateArguments)
        let traceOutput = TracingPolicy.toolOutput(name: "search_profile", result: searchResult)
        let tracePayload: [String: JSONValue] = ["input": .object(traceInput), "output": .object(traceOutput)]
        let traceText = String(data: try JSONEncoder().encode(tracePayload), encoding: .utf8) ?? ""
        try require(!traceText.contains("private-profile-value"), "Profile query leaked into trace metadata")
        try require(!traceText.contains("Example Person"), "Profile result leaked into trace metadata")
        try require(traceText.contains("query_character_count") && traceText.contains("result_count"), "Safe profile trace metrics were missing")
        print("PASS privacy: profile values excluded from trace metadata")

        let malformedURL = directory.appendingPathComponent("malformed.json")
        try Data("{not-json".utf8).write(to: malformedURL)
        do {
            _ = try importer.importSeed(at: malformedURL)
            throw ProfileTestError.failed("Malformed seed was accepted")
        } catch is ProfileImportError { }

        var optionalFixture = fixture
        optionalFixture.address = nil
        optionalFixture.contact.alternateEmail = nil
        try encoder.encode(optionalFixture).write(to: seedURL, options: .atomic)
        _ = try importer.importSeed(at: seedURL)
        let optionalLoaded = try repository.loadPersonalProfile()
        try require(optionalLoaded?.contact.alternateEmail == nil, "Missing optional contact field was not preserved")
        print("PASS validation: malformed input rejected and optional fields supported")

        print("ALL PROFILE TESTS PASSED")
    }

    private static func fictionalProfile() -> PersonalProfile {
        PersonalProfile(
            identity: ProfileIdentity(fullName: "Example Person", firstName: "Example", lastName: "Person", preferredName: "Example", legalName: "Example Person"),
            contact: ProfileContact(primaryEmail: "person@example.invalid", alternateEmail: nil, primaryPhone: "+1-555-0199"),
            address: ProfileAddress(street: "100 Test Street", city: "Test City", state: "Test State", postalCode: "00000", country: "United States"),
            links: [ProfileLinkRecord(id: "example_portfolio", label: "Portfolio", url: "https://example.invalid")],
            education: [EducationRecord(id: "example_degree", institution: "Example University", degree: "BS", major: "Computer Science", startDate: "2020-08", graduationDate: "2024-05", gpa: nil, coursework: ["Python"], activities: [], achievements: [])],
            experience: [
                ExperienceRecord(id: "example_cloud_role", company: "Example Cloud Company", title: "Engineer", employmentType: "Full-time", location: "Remote", startDate: "2024-01", endDate: nil, isCurrent: true, achievements: ["Built an AWS service"], technologies: ["AWS", "Kubernetes", "Python"]),
                ExperienceRecord(id: "example_ai_role", company: "Example AI Company", title: "AI Engineer", employmentType: "Internship", location: "Remote", startDate: "2023-01", endDate: "2023-08", isCurrent: false, achievements: [], technologies: ["RAG"])
            ],
            skills: [SkillCategory(category: "Languages", skills: ["Python", "Go"]), SkillCategory(category: "DevOps", skills: ["Kubernetes"])],
            projects: [
                ProjectRecord(id: "example_go_service", name: "Example Service", technologies: ["Go", "AWS"], repositoryURL: nil, description: nil, highlights: []),
                ProjectRecord(id: "example_rag_project", name: "Example RAG", technologies: ["Python", "RAG"], repositoryURL: nil, description: nil, highlights: [])
            ],
            certifications: [CertificationRecord(id: "example_cert", name: "Example Certification", issuer: nil, type: "certification", issueDate: nil, expirationDate: nil, credentialID: nil, credentialURL: nil, unresolved: false)],
            careerPreferences: CareerPreferences(targetRoles: ["Software Engineer"], preferredLocations: ["Remote"], remote: true, hybrid: false, onsite: false, willingToRelocate: false, preferredIndustries: [], earliestStartDate: nil),
            workAuthorization: WorkAuthorization(country: "United States", currentStatus: nil, authorizationType: nil, authorizationStartDate: nil, authorizationExpirationDate: nil, currentlyRequiredSponsorship: false, futureRequiredSponsorship: false, futureSponsorshipType: nil),
            applicationAnswers: ApplicationAnswers(authorizedToWorkInUS: true, requiresCurrentSponsorship: false, requiresFutureSponsorship: false, willingToRelocate: false, willingToWorkOnsite: false, willingToWorkHybrid: false, willingToWorkRemote: true),
            documents: [ProfileDocument(id: "example_resume", type: "resume", label: "Example Resume", filename: nil, path: nil, preferred: true, lastUpdated: nil)]
        )
    }
}
