import Foundation

enum CalendarToolSupport {
    static let maximumRange: TimeInterval = 90 * 24 * 60 * 60

    static func object(_ arguments: JSONValue, allowedKeys: Set<String>) throws -> [String: JSONValue] {
        guard case .object(let object) = arguments else {
            throw AgentToolError.invalidArguments("Arguments must be a JSON object.")
        }
        let unexpected = Set(object.keys).subtracting(allowedKeys)
        guard unexpected.isEmpty else {
            throw AgentToolError.invalidArguments("Unexpected arguments: \(unexpected.sorted().joined(separator: ", ")).")
        }
        return object
    }

    static func range(in object: [String: JSONValue]) throws -> (Date, Date) {
        let start = try date("start", in: object)
        let end = try date("end", in: object)
        guard end > start else { throw AgentToolError.invalidArguments("end must be later than start.") }
        guard end.timeIntervalSince(start) <= maximumRange else {
            throw AgentToolError.invalidArguments("Calendar ranges may not exceed 90 days.")
        }
        return (start, end)
    }

    static func query(in object: [String: JSONValue]) throws -> String {
        guard case .string(let rawValue) = object["query"] else {
            throw AgentToolError.invalidArguments("query must be a non-empty string.")
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw AgentToolError.invalidArguments("query must be a non-empty string.") }
        return value
    }

    static func limit(in object: [String: JSONValue], default value: Int) throws -> Int {
        guard let raw = object["limit"] else { return value }
        guard case .number(let number) = raw, number.rounded() == number, (1...50).contains(Int(number)) else {
            throw AgentToolError.invalidArguments("limit must be an integer from 1 through 50.")
        }
        return Int(number)
    }

    static func accessFailure(_ status: CalendarAuthorizationStatus) -> JSONValue? {
        let reason: String? = switch status {
        case .authorized: nil
        case .notDetermined: "calendar_access_not_determined"
        case .denied: "calendar_access_denied"
        case .restricted: "calendar_access_restricted"
        case .unavailable: "calendar_access_unavailable"
        }
        return reason.map { .object(["success": .bool(false), "reason": .string($0)]) }
    }

    static func result(events: [CalendarEvent], rangeStart: Date, rangeEnd: Date, limit: Int) -> JSONValue {
        let limited = Array(events.prefix(limit))
        let relationships = limited.map { CalendarRangeRelationship.classify(event: $0, rangeStart: rangeStart, rangeEnd: rangeEnd) }
        return .object([
            "success": .bool(true),
            "range": .object([
                "start": .string(RepositoryDate.encode(rangeStart)),
                "end": .string(RepositoryDate.encode(rangeEnd))
            ]),
            "events": .array(zip(limited, relationships).map { json($0.0, relationship: $0.1) }),
            "result_count": .number(Double(limited.count)),
            "starting_event_count": .number(Double(relationships.filter { $0 == .startsWithinRange }.count)),
            "continuing_event_count": .number(Double(relationships.filter { $0 != .startsWithinRange }.count)),
            "limit_reached": .bool(events.count > limited.count)
        ])
    }

    static func requiredTitle(in object: [String: JSONValue]) throws -> String {
        let title = try requiredString("title", in: object)
        guard title.count <= 300 else { throw AgentToolError.invalidArguments("title is too long.") }
        return title
    }

    static func requiredString(_ key: String, in object: [String: JSONValue]) throws -> String {
        guard case .string(let raw) = object[key] else { throw AgentToolError.invalidArguments("\(key) is required.") }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw AgentToolError.invalidArguments("\(key) must be a non-empty string.") }
        return value
    }

    static func optionalString(_ key: String, in object: [String: JSONValue]) throws -> String? {
        guard let raw = object[key] else { return nil }
        guard case .string(let value) = raw else { throw AgentToolError.invalidArguments("\(key) must be a string.") }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func optionalBool(_ key: String, in object: [String: JSONValue]) throws -> Bool? {
        guard let raw = object[key] else { return nil }
        guard case .bool(let value) = raw else { throw AgentToolError.invalidArguments("\(key) must be a boolean.") }
        return value
    }

    static func optionalDate(_ key: String, in object: [String: JSONValue]) throws -> Date? {
        guard object[key] != nil else { return nil }
        return try date(key, in: object)
    }

    static func proposal(_ action: PendingAction) -> JSONValue {
        .object(["success": .bool(true), "approval_required": .bool(true), "pending_action_id": .string(action.id.uuidString), "summary": .string(action.summary)])
    }

    static func date(_ key: String, in object: [String: JSONValue]) throws -> Date {
        guard case .string(let source) = object[key], let value = ISO8601DateFormatter().date(from: source) else {
            throw AgentToolError.invalidArguments("\(key) must be an ISO-8601 date-time with a timezone offset.")
        }
        return value
    }

    private static func json(_ event: CalendarEvent, relationship: CalendarRangeRelationship) -> JSONValue {
        var object: [String: JSONValue] = [
            "event_reference": .string(event.id), "title": .string(event.title),
            "start": .string(RepositoryDate.encode(event.startDate)),
            "end": .string(RepositoryDate.encode(event.endDate)),
            "is_all_day": .bool(event.isAllDay),
            "calendar_name": .string(event.calendarName),
            "range_relationship": .string(relationship.rawValue)
        ]
        if let location = event.location { object["location"] = .string(location) }
        return .object(object)
    }
}
