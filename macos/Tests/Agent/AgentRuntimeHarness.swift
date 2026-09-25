import Foundation

private enum HarnessError: Error {
    case assertion(String)
}

private actor MockNebiusClient: NebiusServing {
    private(set) var requestCount = 0
    private(set) var receivedLocalToolResult = false

    func fetchModels() async throws -> [AvailableModel] {
        // The runtime must ignore both the non-NVIDIA and non-Nemotron entries.
        [
            AvailableModel(id: "another-provider/model"),
            AvailableModel(id: "nvidia/other-model"),
            AvailableModel(id: "nvidia/Nemotron-3.5-Lightning-30B-A3B")
        ]
    }

    func createChatCompletion(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        requestCount += 1
        guard request.model == "nvidia/Nemotron-3.5-Lightning-30B-A3B" else {
            throw HarnessError.assertion("Runtime selected the wrong model")
        }
        guard request.tools?.contains(where: { $0.function.name == "get_current_project" }) == true else {
            throw HarnessError.assertion("Tool definition was not sent")
        }

        if requestCount == 1 {
            let call = ToolCall(
                id: "call_project_1",
                type: "function",
                function: ToolCallFunction(name: "get_current_project", arguments: "{}")
            )
            return ChatCompletionResponse(choices: [
                ChatChoice(
                    message: ChatMessage(role: "assistant", toolCalls: [call]),
                    finishReason: "tool_calls"
                )
            ])
        }

        guard request.messages.count >= 2 else {
            throw HarnessError.assertion("Tool exchange is missing from conversation history")
        }
        let assistantCall = request.messages[request.messages.count - 2]
        let toolResult = request.messages[request.messages.count - 1]
        guard assistantCall.role == "assistant",
              assistantCall.toolCalls?.first?.id == "call_project_1",
              toolResult.role == "tool",
              toolResult.toolCallID == "call_project_1",
              toolResult.name == "get_current_project",
              let content = toolResult.content,
              let data = content.data(using: .utf8),
              case .object(let result) = try JSONDecoder().decode(JSONValue.self, from: data),
              result["name"] == .string("Personal AI"),
              result["platform"] == .string("macOS"),
              result["framework"] == .string("SwiftUI") else {
            throw HarnessError.assertion("Local tool result or tool_call_id was incorrect")
        }

        receivedLocalToolResult = true
        return ChatCompletionResponse(choices: [
            ChatChoice(
                message: ChatMessage(
                    role: "assistant",
                    content: "You are currently working on Personal AI, a macOS application built using SwiftUI."
                ),
                finishReason: "stop"
            )
        ])
    }
}

private actor EventRecorder {
    private var events: [AgentExecutionState] = []

    func append(_ event: AgentExecutionState) { events.append(event) }
    func snapshot() -> [AgentExecutionState] { events }
}

@main
private struct AgentRuntimeHarness {
    static func main() async throws {
        let client = MockNebiusClient()
        let events = EventRecorder()
        let runtime = AgentRuntime(client: client, tools: [TestTool()])
        let answer = try await runtime.send(
            userMessage: "Use get_current_project and tell me what project I am currently working on."
        ) { event in
            await events.append(event)
        }

        let recordedEvents = await events.snapshot()
        guard await client.requestCount == 2,
              await client.receivedLocalToolResult,
              recordedEvents.contains(.callingTool("get_current_project")),
              recordedEvents.contains(.toolCompleted("get_current_project")),
              recordedEvents.last == .completed else {
            throw HarnessError.assertion("The expected end-to-end tool loop did not occur")
        }

        print("PASS: model requested get_current_project")
        print("PASS: Swift executed TestTool and returned matching tool_call_id")
        print("PASS: model produced final response after receiving local JSON")
        print("Final response: \(answer)")
    }
}
