import Foundation

struct CreateCalendarEventTool: AgentTool {
    let name = "create_calendar_event"
    let description = "Proposes a calendar event creation for explicit user approval. It never creates an event by itself. Use a concrete ISO-8601 range and then tell the user to approve the native confirmation card. Do not use Markdown tables, IDs, or tool metadata in the normal response."
    let parameterSchema = CalendarWriteSchemas.create
    let store: CalendarStore; let actions: PendingActionStore
    func execute(arguments: JSONValue) async throws -> JSONValue {
        let object = try CalendarToolSupport.object(arguments, allowedKeys: ["title", "start", "end", "all_day", "location", "calendar_id", "notes"])
        let title = try CalendarToolSupport.requiredTitle(in: object); let start = try CalendarToolSupport.date("start", in: object); let end = try CalendarToolSupport.date("end", in: object)
        guard end > start, end.timeIntervalSince(start) <= 7 * 24 * 3600 else { throw AgentToolError.invalidArguments("The event range is invalid or too long.") }
        let draft = CalendarEventDraft(title: title, startDate: start, endDate: end, isAllDay: try CalendarToolSupport.optionalBool("all_day", in: object) ?? false, location: try CalendarToolSupport.optionalString("location", in: object), notes: try CalendarToolSupport.optionalString("notes", in: object), calendarID: try CalendarToolSupport.optionalString("calendar_id", in: object))
        return try await MainActor.run {
            try store.validate(.create(draft))
            let action = PendingAction(kind: .calendarCreate, summary: "Create Calendar Event", details: [title, CalendarPresentation.dateRange(start: start, end: end, allDay: draft.isAllDay)], isDestructive: false, calendarMutation: .create(draft)); actions.propose(action); return CalendarToolSupport.proposal(action)
        }
    }
}

struct UpdateCalendarEventTool: AgentTool {
    let name = "update_calendar_event"
    let description = "Proposes an update to one exact event_reference previously returned by a Calendar read tool. It never changes an event by itself. Do not guess an event reference; if candidates are ambiguous, ask the user first. Recurring events are not supported for mutation in V2."
    let parameterSchema = CalendarWriteSchemas.update
    let store: CalendarStore; let actions: PendingActionStore
    func execute(arguments: JSONValue) async throws -> JSONValue {
        let object = try CalendarToolSupport.object(arguments, allowedKeys: ["event_reference", "title", "start", "end", "all_day", "location", "notes"])
        let reference = try CalendarToolSupport.requiredString("event_reference", in: object)
        let update = CalendarEventUpdate(eventReference: reference, title: try CalendarToolSupport.optionalString("title", in: object), startDate: try CalendarToolSupport.optionalDate("start", in: object), endDate: try CalendarToolSupport.optionalDate("end", in: object), isAllDay: try CalendarToolSupport.optionalBool("all_day", in: object), location: try CalendarToolSupport.optionalString("location", in: object), notes: try CalendarToolSupport.optionalString("notes", in: object))
        guard update.title != nil || update.startDate != nil || update.endDate != nil || update.isAllDay != nil || update.location != nil || update.notes != nil else { throw AgentToolError.invalidArguments("Provide at least one field to update.") }
        if let start = update.startDate, let end = update.endDate, end <= start { throw AgentToolError.invalidArguments("end must be later than start.") }
        return try await MainActor.run {
            let event = try store.event(reference: reference)
            try store.validate(.update(update))
            let action = PendingAction(kind: .calendarUpdate, summary: "Update Calendar Event", details: [event.title, "Changes will be applied after approval"], isDestructive: false, calendarMutation: .update(update)); actions.propose(action); return CalendarToolSupport.proposal(action)
        }
    }
}

struct DeleteCalendarEventTool: AgentTool {
    let name = "delete_calendar_event"
    let description = "Proposes deletion of one exact event_reference previously returned by a Calendar read tool. It never deletes by itself. Never use a fuzzy title or guess; resolve ambiguity with the user first. Recurring events are not supported for mutation in V2."
    let parameterSchema = CalendarWriteSchemas.delete
    let store: CalendarStore; let actions: PendingActionStore
    func execute(arguments: JSONValue) async throws -> JSONValue {
        let object = try CalendarToolSupport.object(arguments, allowedKeys: ["event_reference"]); let reference = try CalendarToolSupport.requiredString("event_reference", in: object)
        return try await MainActor.run {
            let event = try store.event(reference: reference)
            try store.validate(.delete(CalendarEventDeletion(eventReference: reference)))
            let action = PendingAction(kind: .calendarDelete, summary: "Delete Calendar Event", details: [event.title, CalendarPresentation.dateRange(start: event.startDate, end: event.endDate, allDay: event.isAllDay)], isDestructive: true, calendarMutation: .delete(CalendarEventDeletion(eventReference: reference))); actions.propose(action); return CalendarToolSupport.proposal(action)
        }
    }
}

private enum CalendarWriteSchemas {
    static let create: JSONValue = schema(properties: ["title": "string", "start": "string", "end": "string", "all_day": "boolean", "location": "string", "calendar_id": "string", "notes": "string"], required: ["title", "start", "end"])
    static let update: JSONValue = schema(properties: ["event_reference": "string", "title": "string", "start": "string", "end": "string", "all_day": "boolean", "location": "string", "notes": "string"], required: ["event_reference"])
    static let delete: JSONValue = schema(properties: ["event_reference": "string"], required: ["event_reference"])
    static func schema(properties: [String: String], required: [String]) -> JSONValue { .object(["type": .string("object"), "properties": .object(Dictionary(uniqueKeysWithValues: properties.map { ($0.key, .object(["type": .string($0.value)])) })), "required": .array(required.map(JSONValue.string)), "additionalProperties": .bool(false)]) }
}
