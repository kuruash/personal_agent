import Foundation

protocol NebiusServing: Sendable {
    func fetchModels() async throws -> [AvailableModel]
    func createChatCompletion(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse
}

enum NebiusClientError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case http(statusCode: Int, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "NEBIUS_API_KEY is not set. Add it to the PersonalAI scheme environment variables."
        case .invalidResponse:
            "Nebius returned an invalid HTTP response."
        case .http(let statusCode, let message):
            "Nebius request failed (HTTP \(statusCode)): \(message)"
        case .decoding(let message):
            "Could not decode the Nebius response: \(message)"
        }
    }
}

struct NebiusClient: NebiusServing {
    static let baseURL = URL(string: "https://api.tokenfactory.nebius.com/v1")!

    private let apiKey: String
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        apiKey: String? = ProcessInfo.processInfo.environment["NEBIUS_API_KEY"],
        session: URLSession = .shared
    ) throws {
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NebiusClientError.missingAPIKey
        }
        self.apiKey = apiKey
        self.session = session
    }

    func fetchModels() async throws -> [AvailableModel] {
        let request = authorizedRequest(path: "models", method: "GET")
        let response: ModelsResponse = try await send(request)
        return response.data
    }

    func createChatCompletion(_ completion: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        var request = authorizedRequest(path: "chat/completions", method: "POST")
        request.httpBody = try encoder.encode(completion)
        return try await send(request)
    }

    private func authorizedRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NebiusClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let apiMessage = (try? decoder.decode(APIErrorEnvelope.self, from: data).error.message)
            throw NebiusClientError.http(
                statusCode: http.statusCode,
                message: apiMessage ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw NebiusClientError.decoding(error.localizedDescription)
        }
    }
}
