import Foundation
import os

protocol AgentTracer: Sendable {
    func startRoot(conversationID: UUID?, userMessage: String) async -> TraceRunToken
    func startModel(parent: TraceRunToken, modelID: String, iteration: Int, messageCount: Int, toolCount: Int) async -> TraceRunToken
    func startTool(parent: TraceRunToken, name: String, arguments: JSONValue?) async -> TraceRunToken
    func complete(_ run: TraceRunToken, with completion: TraceCompletion) async
    func flush() async
}

struct NoOpTracer: AgentTracer {
    func startRoot(conversationID: UUID?, userMessage: String) async -> TraceRunToken {
        TraceRunToken.root(name: "PersonalAI Agent", type: .chain)
    }

    func startModel(parent: TraceRunToken, modelID: String, iteration: Int, messageCount: Int, toolCount: Int) async -> TraceRunToken {
        TraceRunToken.child(parent: parent, name: "Nemotron Call", type: .llm)
    }

    func startTool(parent: TraceRunToken, name: String, arguments: JSONValue?) async -> TraceRunToken {
        TraceRunToken.child(parent: parent, name: "Tool: \(name)", type: .tool)
    }

    func complete(_ run: TraceRunToken, with completion: TraceCompletion) async {}
    func flush() async {}
}

struct LangSmithConfiguration: Sendable {
    let apiKey: String
    let project: String
    let endpoint: URL

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> LangSmithConfiguration? {
        guard Self.isTruthy(environment["LANGSMITH_TRACING"]),
              let apiKey = environment["LANGSMITH_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else { return nil }
        let project = environment["LANGSMITH_PROJECT"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointText = environment["LANGSMITH_ENDPOINT"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = endpointText.flatMap(URL.init(string:)) ?? URL(string: "https://api.smith.langchain.com")!
        return LangSmithConfiguration(
            apiKey: apiKey,
            project: project?.isEmpty == false ? project! : "default",
            endpoint: endpoint
        )
    }

    private static func isTruthy(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["1", "true", "yes", "on"].contains(value.lowercased())
    }
}

protocol TracingTransport: Sendable {
    func send(_ request: URLRequest) async throws
}

struct URLSessionTracingTransport: TracingTransport {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func send(_ request: URLRequest) async throws {
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

actor LangSmithTracer: AgentTracer {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.personalai.app",
        category: "PersonalAI.Tracing"
    )

    private let configuration: LangSmithConfiguration
    private let transport: any TracingTransport
    private let encoder = JSONEncoder()
    private var pending: Task<Void, Never>?

    init(configuration: LangSmithConfiguration, transport: any TracingTransport = URLSessionTracingTransport()) {
        self.configuration = configuration
        self.transport = transport
        #if DEBUG
        Self.logger.notice("[Tracing] LangSmith enabled")
        #endif
    }

    func startRoot(conversationID: UUID?, userMessage: String) async -> TraceRunToken {
        let token = TraceRunToken.root(name: "PersonalAI Agent", type: .chain)
        enqueueStart(token, inputs: TracingPolicy.rootInputs(userMessage: userMessage), metadata: TracingPolicy.rootMetadata(conversationID: conversationID))
        debugLog("[Tracing] Root run started")
        return token
    }

    func startModel(parent: TraceRunToken, modelID: String, iteration: Int, messageCount: Int, toolCount: Int) async -> TraceRunToken {
        let token = child(parent: parent, name: "Nemotron Call", type: .llm)
        enqueueStart(
            token,
            inputs: TracingPolicy.modelInputs(messageCount: messageCount, toolCount: toolCount),
            metadata: TracingPolicy.modelMetadata(modelID: modelID, iteration: iteration)
        )
        return token
    }

    func startTool(parent: TraceRunToken, name: String, arguments: JSONValue?) async -> TraceRunToken {
        let token = child(parent: parent, name: "Tool: \(name)", type: .tool)
        enqueueStart(
            token,
            inputs: TracingPolicy.toolInputs(name: name, arguments: arguments),
            metadata: ["tool_name": .string(name)]
        )
        return token
    }

    func complete(_ run: TraceRunToken, with completion: TraceCompletion) async {
        var output = completion.output
        output["duration_ms"] = .number(Date().timeIntervalSince(run.startedAt) * 1_000)
        output["success"] = .bool(completion.success)
        let update = LangSmithRunUpdate(
            endTime: Self.timestamp(Date()),
            status: completion.success ? "success" : "error",
            outputs: output,
            error: completion.errorCategory
        )
        enqueue(path: "api/v1/runs/\(run.id.uuidString.lowercased())", method: "PATCH", body: update)
        if run.parentRunID == nil {
            debugLog("[Tracing] Root run completed")
        } else if run.type == .tool {
            debugLog("[Tracing] Tool run completed: \(run.name.replacingOccurrences(of: "Tool: ", with: ""))")
        } else if run.type == .llm {
            debugLog("[Tracing] Model run completed")
        }
    }

    func flush() async {
        await pending?.value
    }

    private func child(parent: TraceRunToken, name: String, type: TraceRunType) -> TraceRunToken {
        TraceRunToken.child(parent: parent, name: name, type: type)
    }

    private func enqueueStart(_ token: TraceRunToken, inputs: [String: JSONValue], metadata: [String: JSONValue]) {
        let payload = LangSmithRunStart(
            id: token.id.uuidString.lowercased(),
            traceID: token.traceID.uuidString.lowercased(),
            parentRunID: token.parentRunID?.uuidString.lowercased(),
            name: token.name, runType: token.type, startTime: Self.timestamp(token.startedAt),
            inputs: inputs, extra: ["metadata": .object(metadata)],
            sessionName: configuration.project, dottedOrder: token.dottedOrder
        )
        enqueue(path: "api/v1/runs", method: "POST", body: payload)
    }

    private func enqueue<Body: Encodable & Sendable>(path: String, method: String, body: Body) {
        let previous = pending
        let configuration = configuration
        let transport = transport
        let encoder = encoder
        pending = Task {
            await previous?.value
            do {
                var request = URLRequest(url: configuration.endpoint.appendingPathComponent(path))
                request.httpMethod = method
                request.timeoutInterval = 5
                request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try encoder.encode(body)
                try await transport.send(request)
            } catch {
                #if DEBUG
                Self.logger.error("[Tracing] LangSmith request failed; continuing without tracing")
                #endif
            }
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        Self.logger.notice("\(message, privacy: .public)")
        #endif
    }
}

enum AgentTracerFactory {
    static func make(environment: [String: String] = ProcessInfo.processInfo.environment) -> any AgentTracer {
        guard let configuration = LangSmithConfiguration.fromEnvironment(environment) else {
            return NoOpTracer()
        }
        return LangSmithTracer(configuration: configuration)
    }
}
