import Foundation

enum TraceRunType: String, Codable, Sendable {
    case chain
    case llm
    case tool
}

struct TraceRunToken: Equatable, Sendable {
    let id: UUID
    let traceID: UUID
    let parentRunID: UUID?
    let name: String
    let type: TraceRunType
    let startedAt: Date
    let dottedOrder: String

    static func root(id: UUID = UUID(), name: String, type: TraceRunType) -> TraceRunToken {
        let date = Date()
        return TraceRunToken(
            id: id, traceID: id, parentRunID: nil, name: name, type: type,
            startedAt: date, dottedOrder: segment(date: date, id: id)
        )
    }

    static func child(parent: TraceRunToken, name: String, type: TraceRunType) -> TraceRunToken {
        let id = UUID()
        let date = Date()
        return TraceRunToken(
            id: id, traceID: parent.traceID, parentRunID: parent.id,
            name: name, type: type, startedAt: date,
            dottedOrder: parent.dottedOrder + "." + segment(date: date, id: id)
        )
    }

    private static func segment(date: Date, id: UUID) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmssSSSSSS'Z'"
        return formatter.string(from: date) + id.uuidString.lowercased()
    }
}

struct TraceCompletion: Sendable {
    let success: Bool
    let output: [String: JSONValue]
    let errorCategory: String?

    static func success(_ output: [String: JSONValue] = [:]) -> TraceCompletion {
        TraceCompletion(success: true, output: output, errorCategory: nil)
    }

    static func failure(category: String) -> TraceCompletion {
        TraceCompletion(success: false, output: [:], errorCategory: category)
    }
}

struct LangSmithRunStart: Encodable, Sendable {
    let id: String
    let traceID: String
    let parentRunID: String?
    let name: String
    let runType: TraceRunType
    let startTime: String
    let inputs: [String: JSONValue]
    let extra: [String: JSONValue]
    let sessionName: String
    let dottedOrder: String

    enum CodingKeys: String, CodingKey {
        case id, name, inputs, extra
        case traceID = "trace_id"
        case parentRunID = "parent_run_id"
        case runType = "run_type"
        case startTime = "start_time"
        case sessionName = "session_name"
        case dottedOrder = "dotted_order"
    }
}

struct LangSmithRunUpdate: Encodable, Sendable {
    let endTime: String
    let status: String
    let outputs: [String: JSONValue]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case status, outputs, error
        case endTime = "end_time"
    }
}
