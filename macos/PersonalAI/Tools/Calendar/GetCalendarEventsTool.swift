import Foundation

struct GetCalendarEventsTool: AgentTool {
    let name = "get_calendar_events"
    let description = "Retrieves local calendar events for an explicit, bounded ISO-8601 start/end date-time range. Results include range_relationship: starts_within_range means the event starts in the requested interval; continues_into_range or spans_entire_range means it began earlier. For schedule questions, list starts_within_range as the requested day's events and mention carry-over events separately. Never use Markdown tables; use concise prose, time/title blocks, or bullets. Do not show internal identifiers or implementation metadata in normal responses."
    let parameterSchema: JSONValue = .object([
        "type": .string("object"), "properties": .object([
            "start": .object(["type": .string("string"), "format": .string("date-time")]),
            "end": .object(["type": .string("string"), "format": .string("date-time")]),
            "limit": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(50)])
        ]), "required": .array([.string("start"), .string("end")]), "additionalProperties": .bool(false)
    ])
    let store: CalendarStore

    func execute(arguments: JSONValue) async throws -> JSONValue {
        let object = try CalendarToolSupport.object(arguments, allowedKeys: ["start", "end", "limit"])
        let (start, end) = try CalendarToolSupport.range(in: object)
        let limit = try CalendarToolSupport.limit(in: object, default: 50)
        return await MainActor.run {
            store.refreshStatus()
            if let failure = CalendarToolSupport.accessFailure(store.authorizationStatus) { return failure }
            do { return CalendarToolSupport.result(events: try store.events(from: start, to: end), rangeStart: start, rangeEnd: end, limit: limit) }
            catch { return .object(["success": .bool(false), "reason": .string("calendar_query_failed")]) }
        }
    }
}
