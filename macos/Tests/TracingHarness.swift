import Foundation

private enum TracingTestError: Error { case failed(String), simulatedFailure }
private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TracingTestError.failed(message) }
}

private enum RecordedEvent: Equatable {
    case started(TraceRunToken)
    case completed(TraceRunToken, Bool)
}

private actor RecordingTracer: AgentTracer {
    private var events: [RecordedEvent] = []

    func startRoot(conversationID: UUID?, userMessage: String) async -> TraceRunToken {
        let run = TraceRunToken.root(name: "PersonalAI Agent", type: .chain)
        events.append(.started(run))
        return run
    }

    func startModel(parent: TraceRunToken, modelID: String, iteration: Int, messageCount: Int, toolCount: Int) async -> TraceRunToken {
        let run = TraceRunToken.child(parent: parent, name: "Nemotron Call", type: .llm)
        events.append(.started(run))
        return run
    }

    func startTool(parent: TraceRunToken, name: String, arguments: JSONValue?) async -> TraceRunToken {
        let run = TraceRunToken.child(parent: parent, name: "Tool: \(name)", type: .tool)
        events.append(.started(run))
        return run
    }

    func complete(_ run: TraceRunToken, with completion: TraceCompletion) async {
        events.append(.completed(run, completion.success))
    }

    func flush() async {}
    func snapshot() -> [RecordedEvent] { events }
}

private actor ToolCallingClient: NebiusServing {
    private var requestCount = 0

    func fetchModels() async throws -> [AvailableModel] {
        [AvailableModel(id: "nvidia/Nemotron-Tracing-Test")]
    }

    func createChatCompletion(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        requestCount += 1
        if requestCount == 1 {
            return ChatCompletionResponse(choices: [
                ChatChoice(
                    message: ChatMessage(
                        role: "assistant",
                        toolCalls: [ToolCall(
                            id: "trace-tool-1", type: "function",
                            function: ToolCallFunction(name: "get_current_project", arguments: "{}")
                        )]
                    ),
                    finishReason: "tool_calls"
                )
            ], usage: ChatUsage(promptTokens: 12, completionTokens: 4, totalTokens: 16))
        }
        return ChatCompletionResponse(choices: [
            ChatChoice(message: ChatMessage(role: "assistant", content: "Completed safely."), finishReason: "stop")
        ], usage: ChatUsage(promptTokens: 20, completionTokens: 3, totalTokens: 23))
    }
}

private actor CapturingTransport: TracingTransport {
    private let failure: Error?
    private var requests: [URLRequest] = []

    init(failure: Error? = nil) { self.failure = failure }

    func send(_ request: URLRequest) async throws {
        requests.append(request)
        if let failure { throw failure }
    }

    func snapshot() -> [URLRequest] { requests }
}

@main
private struct TracingHarness {
    static func main() async throws {
        let recorder = RecordingTracer()
        let conversationID = UUID()
        let runtime = AgentRuntime(
            client: ToolCallingClient(), tools: [TestTool()], tracer: recorder,
            conversationID: conversationID
        )
        let answer = try await runtime.send(userMessage: "Use the local project tool.")
        try require(answer == "Completed safely.", "Tracing changed the agent response")

        let events = await recorder.snapshot()
        let starts = events.compactMap { event -> TraceRunToken? in
            if case .started(let run) = event { return run }
            return nil
        }
        try require(starts.count == 4, "Expected one root, two model runs, and one tool run")
        guard let root = starts.first(where: { $0.type == .chain }) else {
            throw TracingTestError.failed("Missing root run")
        }
        let children = starts.filter { $0.type != .chain }
        try require(children.allSatisfy { $0.parentRunID == root.id && $0.traceID == root.traceID }, "Child hierarchy was incorrect")
        try require(children.map(\.type) == [.llm, .tool, .llm], "Child execution order was incorrect")
        let completions = events.compactMap { event -> TraceRunToken? in
            if case .completed(let run, true) = event { return run }
            return nil
        }
        try require(completions.count == 4, "Runs did not all complete successfully")
        print("PASS hierarchy: one root with model, tool, model children")

        let disabled = AgentTracerFactory.make(environment: [
            "LANGSMITH_TRACING": "false",
            "LANGSMITH_API_KEY": "must-not-be-used"
        ])
        try require(disabled is NoOpTracer, "Explicitly disabled tracing did not use NoOpTracer")
        let missingKey = AgentTracerFactory.make(environment: ["LANGSMITH_TRACING": "true"])
        try require(missingKey is NoOpTracer, "Missing key did not disable tracing")
        print("PASS disabled: false or missing key selects NoOpTracer")

        let fakeKey = "lsv2_secret_key_must_never_be_payload_data"
        let transport = CapturingTransport()
        let tracer = LangSmithTracer(
            configuration: LangSmithConfiguration(
                apiKey: fakeKey, project: "PersonalAI-Test",
                endpoint: URL(string: "https://example.invalid")!
            ),
            transport: transport
        )
        let privatePrompt = "Private SQLite conversation content"
        let rootRun = await tracer.startRoot(conversationID: UUID(), userMessage: privatePrompt)
        let arguments: JSONValue = .object([
            "path": .string("/Users/fake/Documents/Private/README.md"),
            "bookmark": .string("SECURITY_SCOPED_BOOKMARK_DATA")
        ])
        let toolRun = await tracer.startTool(parent: rootRun, name: "read_file", arguments: arguments)
        let privateResult: JSONValue = .object([
            "content": .string("TOP SECRET RAW FILE CONTENT"),
            "returnedBytes": .number(27),
            "truncated": .bool(false)
        ])
        await tracer.complete(toolRun, with: .success(TracingPolicy.toolOutput(name: "read_file", result: privateResult)))
        await tracer.complete(rootRun, with: .success(["character_count": .number(10)]))
        await tracer.flush()

        let requests = await transport.snapshot()
        let payloadText = requests.compactMap(\.httpBody).compactMap { String(data: $0, encoding: .utf8) }.joined(separator: "\n")
        try require(!payloadText.contains(fakeKey), "API key appeared in a trace payload")
        try require(!payloadText.contains(privatePrompt), "Raw conversation content appeared in a trace payload")
        try require(!payloadText.contains("TOP SECRET RAW FILE CONTENT"), "Raw file content appeared in a trace payload")
        try require(!payloadText.contains("/Users/fake"), "Absolute user path appeared in a trace payload")
        try require(!payloadText.contains("SECURITY_SCOPED_BOOKMARK_DATA"), "Bookmark data appeared in a trace payload")
        try require(payloadText.contains("returned_bytes") && payloadText.contains("truncated"), "Safe tool metadata was not retained")
        try require(requests.allSatisfy { $0.value(forHTTPHeaderField: "X-API-Key") == fakeKey }, "API key was not isolated to the authentication header")
        print("PASS privacy: secrets, content, paths, bookmarks, and prompts excluded; safe metrics retained")

        for failure in [
            URLError(.timedOut), URLError(.notConnectedToInternet),
            TracingTestError.simulatedFailure, URLError(.badServerResponse)
        ] as [Error] {
            let failingTransport = CapturingTransport(failure: failure)
            let failingTracer = LangSmithTracer(
                configuration: LangSmithConfiguration(
                    apiKey: "fake", project: "Failure-Test",
                    endpoint: URL(string: "https://example.invalid")!
                ),
                transport: failingTransport
            )
            let workingRuntime = AgentRuntime(
                client: ToolCallingClient(), tools: [TestTool()], tracer: failingTracer
            )
            let result = try await workingRuntime.send(userMessage: "Continue even if tracing fails.")
            try require(result == "Completed safely.", "Tracing transport failure escaped into AgentRuntime")
            await failingTracer.flush()
        }
        print("PASS failure isolation: timeout, network, HTTP-style, and generic failures did not affect AgentRuntime")
        print("ALL TRACING TESTS PASSED")
    }
}
