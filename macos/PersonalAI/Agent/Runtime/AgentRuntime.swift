import Foundation
import os

enum AgentExecutionState: Equatable, Sendable {
    case thinking
    case callingTool(String)
    case toolCompleted(String)
    case generatingResponse
    case completed
    case failed(String)

    var label: String {
        switch self {
        case .thinking: "Thinking"
        case .callingTool(let name): "Calling \(name)"
        case .toolCompleted: "Tool completed"
        case .generatingResponse: "Generating response"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }
}

enum AgentRuntimeError: LocalizedError {
    case noNemotronModel
    case emptyCompletion
    case missingAssistantContent
    case unknownTool(String)
    case malformedArguments(tool: String, details: String)
    case iterationLimit(Int)

    var errorDescription: String? {
        switch self {
        case .noNemotronModel:
            "Nebius has no available NVIDIA Nemotron model whose ID begins with nvidia/."
        case .emptyCompletion:
            "Nemotron returned no completion choices."
        case .missingAssistantContent:
            "Nemotron returned neither a final response nor a tool call."
        case .unknownTool(let name):
            "Nemotron requested an unavailable tool: \(name)."
        case .malformedArguments(let tool, let details):
            "Nemotron returned invalid arguments for \(tool): \(details)"
        case .iterationLimit(let limit):
            "The agent stopped after \(limit) model turns to prevent an infinite tool loop."
        }
    }
}

actor AgentRuntime {
    typealias StateHandler = @Sendable (AgentExecutionState) async -> Void

    private static let agentLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.personalai.app",
        category: "PersonalAI.Agent"
    )
    private static let systemPrompt = """
        You are Personal AI. Use an available tool whenever the user explicitly asks you to use it. \
        Never invent a tool result. After a tool responds, answer using only the returned data. \
        Use Profile tools when the user asks about their personal, education, professional, career, authorization, or document information. \
        Do not reveal hidden reasoning or chain-of-thought.
        """

    private let client: any NebiusServing
    private let tracer: any AgentTracer
    private let conversationID: UUID?
    private let toolsByName: [String: any AgentTool]
    private let maximumIterations: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var selectedModelID: String?
    private var history: [ChatMessage]

    init(
        client: any NebiusServing,
        tools: [any AgentTool]? = nil,
        maximumIterations: Int = 8,
        restoredHistory: [ChatMessage] = [],
        tracer: any AgentTracer = AgentTracerFactory.make(),
        conversationID: UUID? = nil,
        profileStore: ProfileStore? = nil
    ) {
        self.client = client
        self.tracer = tracer
        self.conversationID = conversationID
        var defaultTools: [any AgentTool] = [
            TestTool(), ListDirectoryTool(), SearchFilesTool(), GetFileInfoTool(), ReadFileTool()
        ]
        if let profileStore {
            defaultTools.append(GetProfileIndexTool(store: profileStore))
            defaultTools.append(GetProfileSectionTool(store: profileStore))
            defaultTools.append(SearchProfileTool(store: profileStore))
        }
        let registeredTools = tools ?? defaultTools
        self.toolsByName = Dictionary(uniqueKeysWithValues: registeredTools.map { ($0.name, $0) })
        self.maximumIterations = maximumIterations
        self.history = [ChatMessage(role: "system", content: Self.systemPrompt)] +
            restoredHistory.filter { $0.role != "system" }
        debugLog("[Agent] AgentRuntime initialized")
    }

    func resetConversation() {
        history = [ChatMessage(role: "system", content: Self.systemPrompt)]
    }

    func currentModelID() -> String? {
        selectedModelID
    }

    /// Returns the exact model-visible history, excluding the system prompt so the
    /// current application prompt is always used when a saved conversation is restored.
    func historyForPersistence() -> [ChatMessage] {
        history.filter { $0.role != "system" }
    }

    func send(userMessage: String, onState: StateHandler? = nil) async throws -> String {
        await onState?(.thinking)
        let rootRun = await tracer.startRoot(conversationID: conversationID, userMessage: userMessage)

        do {
            let modelID = try await resolveNemotronModel()
            history.append(ChatMessage(role: "user", content: userMessage))
            var hasPendingToolResult = false

            for iteration in 1...maximumIterations {
                if iteration > 1 { await onState?(.generatingResponse) }

                let isFollowUpRequest = hasPendingToolResult
                if hasPendingToolResult {
                    debugLog("[Agent] Sending tool result to Nemotron")
                    hasPendingToolResult = false
                }

                let request = ChatCompletionRequest(
                    model: modelID,
                    messages: history,
                    tools: toolsByName.values.map(\.definition).sorted { $0.function.name < $1.function.name },
                    toolChoice: "auto"
                )
                if isFollowUpRequest {
                    debugLog("[Agent] Sending follow-up request to Nemotron")
                } else {
                    debugLog("[Agent] Sending request to Nemotron")
                }
                let modelRun = await tracer.startModel(
                    parent: rootRun,
                    modelID: modelID,
                    iteration: iteration,
                    messageCount: history.count,
                    toolCount: toolsByName.count
                )
                let completion: ChatCompletionResponse
                do {
                    completion = try await client.createChatCompletion(request)
                    await tracer.complete(
                        modelRun,
                        with: .success(TracingPolicy.modelOutput(response: completion))
                    )
                } catch {
                    await tracer.complete(
                        modelRun,
                        with: .failure(category: TracingPolicy.errorCategory(error))
                    )
                    throw error
                }
                guard let assistantMessage = completion.choices.first?.message else {
                    throw AgentRuntimeError.emptyCompletion
                }

                if let calls = assistantMessage.toolCalls, !calls.isEmpty {
                    // The assistant tool-call message must precede every matching tool result.
                    history.append(assistantMessage)
                    for call in calls {
                        debugLog("[Agent] Nemotron requested tool: \(call.function.name)")
                        debugLog("[Agent] Tool call ID: \(call.id)")
                        try await execute(call, parentRun: rootRun, onState: onState)
                    }
                    hasPendingToolResult = true
                    continue
                }

                guard let content = assistantMessage.content,
                      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw AgentRuntimeError.missingAssistantContent
                }
                history.append(assistantMessage)
                debugLog("[Agent] Nemotron returned final response")
                await tracer.complete(
                    rootRun,
                    with: .success(TracingPolicy.rootOutput(response: content, modelID: selectedModelID))
                )
                await onState?(.completed)
                return content
            }

            throw AgentRuntimeError.iterationLimit(maximumIterations)
        } catch {
            await tracer.complete(
                rootRun,
                with: .failure(category: TracingPolicy.errorCategory(error))
            )
            await onState?(.failed(error.localizedDescription))
            throw error
        }
    }

    private func resolveNemotronModel() async throws -> String {
        if let selectedModelID { return selectedModelID }

        let candidates = try await client.fetchModels()
            .map(\.id)
            .filter {
                $0.hasPrefix("nvidia/") &&
                $0.localizedCaseInsensitiveContains("nemotron")
            }

        guard let selected = candidates.sorted(by: modelPreference).first else {
            throw AgentRuntimeError.noNemotronModel
        }
        selectedModelID = selected
        return selected
    }

    private nonisolated func modelPreference(_ lhs: String, _ rhs: String) -> Bool {
        func score(_ id: String) -> Int {
            let value = id.lowercased()
            let preferences = ["ultra", "super", "253b", "70b", "49b", "32b", "12b", "9b", "4b", "nano"]
            return preferences.firstIndex(where: value.contains).map { preferences.count - $0 } ?? 0
        }
        let leftScore = score(lhs)
        let rightScore = score(rhs)
        return leftScore == rightScore ? lhs > rhs : leftScore > rightScore
    }

    private func execute(
        _ call: ToolCall,
        parentRun: TraceRunToken,
        onState: StateHandler?
    ) async throws {
        let toolName = call.function.name
        let decodedArguments = try? decoder.decode(JSONValue.self, from: Data(call.function.arguments.utf8))
        let toolRun = await tracer.startTool(parent: parentRun, name: toolName, arguments: decodedArguments)
        let result: JSONValue
        var toolFailureCategory: String?
        do {
            guard let tool = toolsByName[toolName] else {
                throw AgentRuntimeError.unknownTool(toolName)
            }
            let arguments: JSONValue
            do {
                arguments = try decoder.decode(JSONValue.self, from: Data(call.function.arguments.utf8))
            } catch {
                throw AgentRuntimeError.malformedArguments(tool: toolName, details: error.localizedDescription)
            }

            await onState?(.callingTool(toolName))
            debugLog("[Agent] Executing Swift tool: \(toolName)")
            result = try await tool.execute(arguments: arguments)
        } catch {
            toolFailureCategory = TracingPolicy.errorCategory(error)
            result = .object([
                "error": .string(error.localizedDescription),
                "tool": .string(toolName)
            ])
        }
        let traceOutput = TracingPolicy.toolOutput(name: toolName, result: result)
        if let toolFailureCategory {
            await tracer.complete(toolRun, with: .failure(category: toolFailureCategory))
        } else {
            await tracer.complete(toolRun, with: .success(traceOutput))
        }
        let resultData = try encoder.encode(result)
        guard let resultText = String(data: resultData, encoding: .utf8) else {
            throw AgentRuntimeError.malformedArguments(tool: toolName, details: "Tool result was not UTF-8 JSON.")
        }
        if toolName == "get_current_project" {
            debugLog("[Agent] Tool result: \(resultText)")
        }
        history.append(ChatMessage(
            role: "tool",
            content: resultText,
            toolCallID: call.id,
            name: toolName
        ))
        debugLog("[Agent] Tool completed: \(toolName)")
        await onState?(.toolCompleted(toolName))
    }

    private nonisolated func debugLog(_ message: String) {
        #if DEBUG
        Self.agentLogger.notice("\(message, privacy: .public)")
        #endif
    }
}
