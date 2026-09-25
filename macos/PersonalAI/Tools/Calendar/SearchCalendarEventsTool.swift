import Foundation

struct SearchCalendarEventsTool: AgentTool {
    let name = "search_calendar_events"
    let description = "Searches local calendar event titles, locations, and calendar names in an explicit bounded ISO-8601 start/end date-time range. Results label events that begin in the interval versus events that carry into it; describe those separately for schedule questions. Never use Markdown tables and do not show internal identifiers or implementation metadata in normal responses."
    let parameterSchema: JSONValue = .object([
        "type": .string("object"), "properties": .object([
            "query": .object(["type": .string("string"), "minLength": .number(1)]),
            "start": .object(["type": .string("string"), "format": .string("date-time")]),
            "end": .object(["type": .string("string"), "format": .string("date-time")]),
            "limit": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(50)])
        ]), "required": .array([.string("query"), .string("start"), .string("end")]), "additionalProperties": .bool(false)
    ])
    let store: CalendarStore

    func execute(arguments: JSONValue) async throws -> JSONValue {
        let object = try CalendarToolSupport.object(arguments, allowedKeys: ["query", "start", "end", "limit"])
        let query = try CalendarToolSupport.query(in: object)
        let (start, end) = try CalendarToolSupport.range(in: object)
        let limit = try CalendarToolSupport.limit(in: object, default: 20)
        return await MainActor.run {
            store.refreshStatus()
            if let failure = CalendarToolSupport.accessFailure(store.authorizationStatus) { return failure }
            do {
                let matches = try store.events(from: start, to: end).filter { event in
                    [event.title, event.location, event.calendarName].compactMap { $0 }
                        .contains { $0.localizedCaseInsensitiveContains(query) }
                }
                return CalendarToolSupport.result(events: matches, rangeStart: start, rangeEnd: end, limit: limit)
            } catch { return .object(["success": .bool(false), "reason": .string("calendar_query_failed")]) }
        }
    }
}
