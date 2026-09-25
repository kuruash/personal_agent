import Foundation

private enum MemoryTestFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String { if case .failed(let message) = self { message } else { "Memory test failed" } }
}

private func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw MemoryTestFailure.failed(message) }
}

private func object(_ value: JSONValue) throws -> [String: JSONValue] {
    guard case .object(let object) = value else { throw MemoryTestFailure.failed("Expected JSON object") }
    return object
}

private func array(_ value: JSONValue?) throws -> [JSONValue] {
    guard case .array(let values) = value else { throw MemoryTestFailure.failed("Expected JSON array") }
    return values
}

private actor MemoryToolCallingClient: NebiusServing {
    private var requestCount = 0

    func fetchModels() async throws -> [AvailableModel] {
        [AvailableModel(id: "nvidia/Nemotron-3.5-Lightning-30B-A3B")]
    }

    func createChatCompletion(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        requestCount += 1
        if requestCount == 1 {
            let names = Set(request.tools?.map { $0.function.name } ?? [])
            let expected = Set(["save_memory", "search_memory", "list_memories", "update_memory", "delete_memory"])
            guard expected.isSubset(of: names) else {
                throw MemoryTestFailure.failed("Memory tools were not registered with AgentRuntime")
            }
            return ChatCompletionResponse(choices: [ChatChoice(
                message: ChatMessage(role: "assistant", toolCalls: [ToolCall(
                    id: "memory-call-1", type: "function",
                    function: ToolCallFunction(name: "search_memory", arguments: "{\"query\":\"technical explanations\",\"limit\":5}")
                )]), finishReason: "tool_calls"
            )])
        }
        guard let toolMessage = request.messages.last,
              toolMessage.role == "tool", toolMessage.name == "search_memory",
              toolMessage.toolCallID == "memory-call-1",
              toolMessage.content?.contains("short technical explanations") == true else {
            throw MemoryTestFailure.failed("AgentRuntime did not return Memory tool data to the model")
        }
        return ChatCompletionResponse(choices: [ChatChoice(
            message: ChatMessage(role: "assistant", content: "You prefer short technical explanations."),
            finishReason: "stop"
        )])
    }
}

@main
private struct MemoryHarness {
    static func main() async throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("PersonalAI-MemoryTests-\(UUID().uuidString)")
        let databaseURL = directory.appendingPathComponent("memory.sqlite")
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }

        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let preMigration = try DatabaseManager(databaseURL: databaseURL)
        let profileRepository = ProfileRepository(database: preMigration)
        let profile = UserProfile(
            fullName: "Example Person", preferredName: "Example", location: "Example City",
            email: "example@example.invalid", phone: nil,
            createdAt: baseDate, updatedAt: baseDate
        )
        try profileRepository.saveProfile(profile)
        let conversation = Conversation(
            title: "Existing Conversation",
            messages: [ConversationMessage(role: .user, content: "Existing message", createdAt: baseDate)],
            createdAt: baseDate, updatedAt: baseDate
        )
        try ConversationRepository(database: preMigration).save(conversation)
        try preMigration.read { connection in
            try connection.execute("DROP TABLE memories;")
            try connection.execute("PRAGMA user_version = 2;")
        }
        preMigration.close()

        let database = try DatabaseManager(databaseURL: databaseURL)
        let version = try database.read { try $0.query("PRAGMA user_version;").first?.integer("user_version") }
        try require(version == 3, "V2 database did not migrate to V3")
        try require(try ProfileRepository(database: database).loadProfile() == profile, "Memory migration changed existing Profile data")
        try require(try ConversationRepository(database: database).loadConversation(id: conversation.id)?.messages.count == 1, "Memory migration changed existing conversation data")
        print("PASS migration: V2 to V3 preserved Profile and conversations")

        let repository = MemoryRepository(database: database)
        let preference = try repository.create(
            content: "I prefer concise interview answers.", type: .preference,
            source: .manualUI, importance: .normal, now: baseDate
        )
        let goal = try repository.create(
            content: "I'm preparing for an Arch interview.", type: .goal,
            source: .agentTool, importance: .high, now: baseDate.addingTimeInterval(1)
        )
        let project = try repository.create(
            content: "I'm building Personal AI.", type: .project,
            source: .userExplicit, importance: .normal, now: baseDate.addingTimeInterval(2)
        )
        try require(preference.wasCreated && goal.wasCreated && project.wasCreated, "Memory creation failed")
        try require(try repository.get(id: preference.memory.id) == preference.memory, "Memory retrieval failed")
        try require(try repository.list().map(\.id) == [project.memory.id, goal.memory.id, preference.memory.id], "Memory ordering was not deterministic")

        let duplicate = try repository.create(
            content: "  i PREFER   concise interview answers.  ", type: .other,
            source: .agentTool, importance: .high
        )
        try require(!duplicate.wasCreated && duplicate.memory.id == preference.memory.id, "Normalized duplicate was inserted")

        let interview = try repository.search("interview", limit: 10)
        try require(Set(interview.map(\.id)) == Set([preference.memory.id, goal.memory.id]), "Memory search did not return the two relevant records")
        try require(!interview.contains { $0.id == project.memory.id }, "Memory search returned an unrelated project")
        try require(try repository.search("interview", limit: 1).count == 1, "Memory search limit was ignored")

        let updated = try repository.update(
            id: project.memory.id, content: "I'm building Personal AI Memory V1.",
            type: .project, importance: .high, now: baseDate.addingTimeInterval(3)
        )
        try require(updated.content.hasSuffix("Memory V1."), "Memory update failed")
        try repository.delete(id: preference.memory.id)
        try require(try repository.get(id: preference.memory.id) == nil, "Memory delete failed")
        print("PASS repository: create, retrieve, list, search, limit, update, delete, and duplicate protection")

        let memoryCountBeforeProfileUpdate = try database.read { try $0.query("SELECT COUNT(*) AS count FROM memories;").first?.integer("count") }
        var changedProfile = profile
        changedProfile.preferredName = "Updated Example"
        changedProfile.updatedAt = baseDate.addingTimeInterval(10)
        try ProfileRepository(database: database).saveProfile(changedProfile)
        let memoryCountAfterProfileUpdate = try database.read { try $0.query("SELECT COUNT(*) AS count FROM memories;").first?.integer("count") }
        try require(memoryCountBeforeProfileUpdate == memoryCountAfterProfileUpdate, "Profile update created or removed Memory rows")
        try require(try ProfileRepository(database: database).loadProfile()?.preferredName == "Updated Example", "Memory operations changed Profile behavior")
        print("PASS separation: Profile and Memory tables remain independent")

        let storeA = MemoryStore(database: database)
        let crossConversation = try storeA.create(
            content: "I prefer short technical explanations.",
            type: .preference, source: .agentTool, importance: .normal
        ).memory
        let storeB = MemoryStore(database: database)
        try require(try storeB.search("technical explanations").contains { $0.id == crossConversation.id }, "A fresh session could not retrieve the persisted memory")
        print("PASS persistence: memory remained available across simulated conversation sessions")

        let saveTool = SaveMemoryTool(store: storeB)
        let searchTool = SearchMemoryTool(store: storeB)
        let listTool = ListMemoriesTool(store: storeB)
        let updateTool = UpdateMemoryTool(store: storeB)
        let deleteTool = DeleteMemoryTool(store: storeB)

        let saveResult = try object(await saveTool.execute(arguments: .object([
            "content": .string("Remember this fictional test context."),
            "type": .string("context"),
            "importance": .string("low")
        ])))
        guard case .object(let savedMemory) = saveResult["memory"],
              case .string(let savedIDText) = savedMemory["id"],
              let savedID = UUID(uuidString: savedIDText) else {
            throw MemoryTestFailure.failed("save_memory returned malformed data")
        }
        let searchResult = try object(await searchTool.execute(arguments: .object([
            "query": .string("fictional context"), "limit": .number(5)
        ])))
        try require(!(try array(searchResult["results"])).isEmpty, "search_memory returned no result")
        let listResult = try object(await listTool.execute(arguments: .object([
            "type": .string("context"), "limit": .number(5)
        ])))
        try require(!(try array(listResult["results"])).isEmpty, "list_memories returned no result")
        _ = try await updateTool.execute(arguments: .object([
            "id": .string(savedID.uuidString), "importance": .string("high")
        ]))
        try require(try storeB.memory(id: savedID)?.importance == .high, "update_memory failed")
        _ = try await deleteTool.execute(arguments: .object(["id": .string(savedID.uuidString)]))
        try require(try storeB.memory(id: savedID) == nil, "delete_memory failed")

        do {
            _ = try await saveTool.execute(arguments: .object([
                "content": .string("Invalid"), "type": .string("preference; DROP TABLE memories")
            ]))
            throw MemoryTestFailure.failed("SQL-like memory type was accepted")
        } catch is AgentToolError { }
        do {
            _ = try await listTool.execute(arguments: .object(["unexpected": .string("value")]))
            throw MemoryTestFailure.failed("Unexpected tool argument was accepted")
        } catch is AgentToolError { }
        do {
            _ = try await deleteTool.execute(arguments: .object(["id": .string(UUID().uuidString)]))
            throw MemoryTestFailure.failed("Unknown memory ID was silently deleted")
        } catch MemoryError.notFound { }
        print("PASS tools: save, search, list, update, delete, strict types, IDs, and schemas")

        let privateContent = "PRIVATE MEMORY CONTENT"
        let privateQuery = "PRIVATE MEMORY QUERY"
        let traceInput = TracingPolicy.toolInputs(
            name: "search_memory", arguments: .object(["query": .string(privateQuery), "type": .string("preference")])
        )
        let traceOutput = TracingPolicy.toolOutput(name: "search_memory", result: .object([
            "results": .array([.object(["content": .string(privateContent), "type": .string("preference")])])
        ]))
        let traceText = String(data: try JSONEncoder().encode(["input": traceInput, "output": traceOutput]), encoding: .utf8) ?? ""
        try require(!traceText.contains(privateContent) && !traceText.contains(privateQuery), "Memory content or query leaked into trace metadata")
        try require(traceText.contains("result_count") && traceText.contains("memory_type"), "Safe Memory trace metadata was missing")
        print("PASS privacy: Memory content, queries, and results excluded from tracing")

        let runtime = AgentRuntime(
            client: MemoryToolCallingClient(), tracer: NoOpTracer(), memoryStore: storeB
        )
        let runtimeAnswer = try await runtime.send(userMessage: "What do you remember about my technical explanation preference?")
        try require(runtimeAnswer == "You prefer short technical explanations.", "Memory tool loop did not complete")
        print("PASS agent integration: Memory tools were registered and tool results completed the runtime loop")

        print("ALL MEMORY TESTS PASSED")
    }
}
