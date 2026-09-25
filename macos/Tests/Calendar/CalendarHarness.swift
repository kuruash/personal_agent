import Foundation

private enum CalendarHarnessError: Error { case failed(String) }
private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CalendarHarnessError.failed(message) }
}
private func object(_ value: JSONValue) throws -> [String: JSONValue] {
    guard case .object(let object) = value else { throw CalendarHarnessError.failed("Expected object") }
    return object
}

@MainActor
private final class FakeCalendarService: CalendarServicing {
    var status: CalendarAuthorizationStatus
    var fixtureEvents: [CalendarEvent]
    var requestedAccess = false
    var authorizationResult: CalendarAuthorizationStatus?
    var requestError: Error?
    var mutationError: Error?
    var recurringReferences: Set<String> = []
    var createCount = 0; var updateCount = 0; var deleteCount = 0

    init(status: CalendarAuthorizationStatus, events: [CalendarEvent]) {
        self.status = status; self.fixtureEvents = events
    }
    func authorizationStatus() -> CalendarAuthorizationStatus { status }
    func requestAccess() async throws -> CalendarAuthorizationStatus {
        requestedAccess = true
        if let requestError { throw requestError }
        if let authorizationResult { status = authorizationResult }
        return status
    }
    func calendarCount() -> Int { status == .authorized ? 2 : 0 }
    func events(from start: Date, to end: Date) throws -> [CalendarEvent] {
        fixtureEvents.filter { $0.startDate < end && $0.endDate > start }
    }
    func event(reference: String) throws -> CalendarEvent { guard let event = fixtureEvents.first(where: { $0.id == reference }) else { throw CalendarMutationError.eventNotFound }; return event }
    func createEvent(_ draft: CalendarEventDraft) throws -> CalendarEvent {
        if let mutationError { throw mutationError }; createCount += 1
        let event = CalendarEvent(id: "created-\(createCount)", title: draft.title, startDate: draft.startDate, endDate: draft.endDate, isAllDay: draft.isAllDay, calendarName: "Work", location: draft.location); fixtureEvents.append(event); return event
    }
    func updateEvent(_ update: CalendarEventUpdate) throws -> CalendarEvent {
        if let mutationError { throw mutationError }; guard let index = fixtureEvents.firstIndex(where: { $0.id == update.eventReference }) else { throw CalendarMutationError.eventNotFound }; updateCount += 1
        let old = fixtureEvents[index]; let event = CalendarEvent(id: old.id, title: update.title ?? old.title, startDate: update.startDate ?? old.startDate, endDate: update.endDate ?? old.endDate, isAllDay: update.isAllDay ?? old.isAllDay, calendarName: old.calendarName, location: update.location ?? old.location); guard event.endDate > event.startDate else { throw CalendarMutationError.invalidMutation }; fixtureEvents[index] = event; return event
    }
    func deleteEvent(_ deletion: CalendarEventDeletion) throws {
        if let mutationError { throw mutationError }; guard let index = fixtureEvents.firstIndex(where: { $0.id == deletion.eventReference }) else { throw CalendarMutationError.eventNotFound }; deleteCount += 1; fixtureEvents.remove(at: index)
    }
    func validate(_ mutation: CalendarMutation) throws {
        if let mutationError { throw mutationError }
        switch mutation {
        case .create: break
        case .update(let update): _ = try event(reference: update.eventReference); if recurringReferences.contains(update.eventReference) { throw CalendarMutationError.recurringEventUnsupported }
        case .delete(let deletion): _ = try event(reference: deletion.eventReference); if recurringReferences.contains(deletion.eventReference) { throw CalendarMutationError.recurringEventUnsupported }
        }
    }
}

private actor CalendarToolClient: NebiusServing {
    private var count = 0
    func fetchModels() async throws -> [AvailableModel] { [AvailableModel(id: "nvidia/Nemotron-3.5-Lightning-30B-A3B")] }
    func createChatCompletion(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        count += 1
        if count == 1 {
            let names = Set(request.tools?.map { $0.function.name } ?? [])
            guard Set(["get_calendar_events", "search_calendar_events"]).isSubset(of: names) else { throw CalendarHarnessError.failed("Calendar tools were not registered") }
            return ChatCompletionResponse(choices: [ChatChoice(message: ChatMessage(role: "assistant", toolCalls: [ToolCall(id: "calendar-1", type: "function", function: ToolCallFunction(name: "search_calendar_events", arguments: "{\"query\":\"arch\",\"start\":\"2026-09-25T00:00:00-04:00\",\"end\":\"2026-09-26T00:00:00-04:00\"}"))]), finishReason: "tool_calls")])
        }
        guard request.messages.last?.content?.contains("Arch Interview") == true else { throw CalendarHarnessError.failed("Calendar result did not reach model") }
        return ChatCompletionResponse(choices: [ChatChoice(message: ChatMessage(role: "assistant", content: "Your Arch Interview is at 2 PM."), finishReason: "stop")])
    }
}

@main
@MainActor
private struct CalendarHarness {
    static func main() async throws {
        let formatter = ISO8601DateFormatter()
        let dayStart = formatter.date(from: "2026-09-25T00:00:00-04:00")!
        let dayEnd = formatter.date(from: "2026-09-26T00:00:00-04:00")!
        let events = [
            CalendarEvent(id: "b", title: "Arch Interview", startDate: formatter.date(from: "2026-09-25T14:00:00-04:00")!, endDate: formatter.date(from: "2026-09-25T15:00:00-04:00")!, isAllDay: false, calendarName: "Work", location: "Private Office"),
            CalendarEvent(id: "a", title: "CS Meeting", startDate: formatter.date(from: "2026-09-25T09:00:00-04:00")!, endDate: formatter.date(from: "2026-09-25T10:00:00-04:00")!, isAllDay: false, calendarName: "School", location: nil),
            CalendarEvent(id: "c", title: "Project Deadline", startDate: dayEnd, endDate: formatter.date(from: "2026-09-27T00:00:00-04:00")!, isAllDay: true, calendarName: "Work", location: nil),
            CalendarEvent(id: "d", title: "Overnight Review", startDate: formatter.date(from: "2026-09-24T23:00:00-04:00")!, endDate: formatter.date(from: "2026-09-25T01:00:00-04:00")!, isAllDay: false, calendarName: "Work", location: nil)
        ]
        let fake = FakeCalendarService(status: .notDetermined, events: events)
        let store = CalendarStore(service: fake)
        fake.authorizationResult = .authorized
        await store.connect()
        try require(fake.requestedAccess && store.authorizationStatus == .authorized && store.permissionErrorMessage == nil, "notDetermined to authorized request did not publish Connected")
        fake.status = .notDetermined; fake.authorizationResult = .denied; fake.requestedAccess = false
        store.refreshStatus(); await store.connect()
        try require(fake.requestedAccess && store.authorizationStatus == .denied && store.permissionErrorMessage == nil, "notDetermined to denied request did not publish denied")
        fake.status = .notDetermined; fake.authorizationResult = nil; fake.requestError = CalendarHarnessError.failed("fake request failure")
        store.refreshStatus(); await store.connect()
        try require(store.authorizationStatus == .notDetermined && store.permissionErrorMessage == "Calendar permission could not be requested." && !store.isRequestingAccess, "Request failure did not produce safe completed failure state")
        fake.requestError = nil; fake.status = .authorized; store.refreshStatus()
        try require(store.authorizationStatus == .authorized && store.calendarCount == 2, "Authorized status did not load")
        print("PASS permission request: authorized, denied, and safe request failure states")
        let dayEvents = try store.events(from: dayStart, to: dayEnd)
        try require(dayEvents.map(\.title) == ["Overnight Review", "CS Meeting", "Arch Interview"], "Overlapping events or deterministic sort failed")
        print("PASS retrieval: same-day, crossing-midnight, all-day boundary, and deterministic sort")

        let get = GetCalendarEventsTool(store: store)
        let search = SearchCalendarEventsTool(store: store)
        let result = try object(await search.execute(arguments: .object(["query": .string("aRcH"), "start": .string("2026-09-25T00:00:00-04:00"), "end": .string("2026-09-26T00:00:00-04:00")])))
        guard case .array(let found) = result["events"], found.count == 1 else { throw CalendarHarnessError.failed("Case-insensitive search failed") }
        let foundEvent = try object(found[0])
        try require(foundEvent["title"] == .string("Arch Interview"), "Search returned wrong event")
        let limited = try object(await get.execute(arguments: .object(["start": .string("2026-09-25T00:00:00-04:00"), "end": .string("2026-09-26T00:00:00-04:00"), "limit": .number(1)])))
        try require(limited["limit_reached"] == .bool(true), "Limit was ignored")
        do { _ = try await get.execute(arguments: .object(["start": .string("2026-01-01T00:00:00Z"), "end": .string("2026-06-01T00:00:00Z")])) ; throw CalendarHarnessError.failed("Oversized range accepted") } catch is AgentToolError {}
        print("PASS tools: search, bounds, limits, and date validation")

        let tomorrowStart = formatter.date(from: "2026-09-26T00:00:00-04:00")!
        let tomorrowEnd = formatter.date(from: "2026-09-27T00:00:00-04:00")!
        fake.fixtureEvents = [
            CalendarEvent(id: "e", title: "Spans Tomorrow", startDate: formatter.date(from: "2026-09-25T20:00:00-04:00")!, endDate: formatter.date(from: "2026-09-27T02:00:00-04:00")!, isAllDay: false, calendarName: "Work", location: nil),
            CalendarEvent(id: "a", title: "OA", startDate: formatter.date(from: "2026-09-25T21:00:00-04:00")!, endDate: formatter.date(from: "2026-09-26T01:00:00-04:00")!, isAllDay: false, calendarName: "Work", location: nil),
            CalendarEvent(id: "c", title: "All-Day Deadline", startDate: tomorrowStart, endDate: tomorrowEnd, isAllDay: true, calendarName: "Work", location: nil),
            CalendarEvent(id: "b", title: "Morning Meeting", startDate: formatter.date(from: "2026-09-26T09:00:00-04:00")!, endDate: formatter.date(from: "2026-09-26T10:00:00-04:00")!, isAllDay: false, calendarName: "Work", location: nil),
            CalendarEvent(id: "d", title: "Late Review", startDate: formatter.date(from: "2026-09-26T23:00:00-04:00")!, endDate: formatter.date(from: "2026-09-27T02:00:00-04:00")!, isAllDay: false, calendarName: "Work", location: nil)
        ]
        let tomorrowResult = try object(await get.execute(arguments: .object([
            "start": .string("2026-09-26T00:00:00-04:00"), "end": .string("2026-09-27T00:00:00-04:00")
        ])))
        guard case .array(let tomorrowEvents) = tomorrowResult["events"] else { throw CalendarHarnessError.failed("Missing tomorrow events") }
        let decodedTomorrow = try tomorrowEvents.map(object)
        try require(decodedTomorrow.map { $0["title"] } == [.string("Spans Tomorrow"), .string("OA"), .string("All-Day Deadline"), .string("Morning Meeting"), .string("Late Review")], "Cross-midnight ordering was not deterministic")
        try require(decodedTomorrow.map { $0["range_relationship"] } == [.string("spans_entire_range"), .string("continues_into_range"), .string("starts_within_range"), .string("starts_within_range"), .string("starts_within_range")], "Range relationships were incorrect")
        try require(decodedTomorrow.allSatisfy { $0["id"] == nil }, "Internal event IDs leaked into model-facing output")
        try require(tomorrowResult["starting_event_count"] == .number(3) && tomorrowResult["continuing_event_count"] == .number(2), "Starting and carry-over counts were incorrect")
        try require(GetCalendarEventsTool(store: store).description.contains("carry-over") && GetCalendarEventsTool(store: store).description.contains("Markdown tables"), "Model tool guidance is incomplete")
        print("PASS date semantics: carry-over, spanning, all-day, starts-within-range, ordering, and ID suppression")

        for state in [CalendarAuthorizationStatus.notDetermined, .denied, .restricted, .unavailable] {
            fake.status = state; store.refreshStatus()
            let response = try object(await get.execute(arguments: .object(["start": .string("2026-09-25T00:00:00-04:00"), "end": .string("2026-09-26T00:00:00-04:00")])))
            try require(response["success"] == .bool(false), "Unauthorized state was not safely returned")
        }
        fake.status = .authorized; store.refreshStatus()
        print("PASS authorization: not-determined, denied, restricted, and unavailable")

        fake.fixtureEvents = events
        let actions = PendingActionStore()
        let create = CreateCalendarEventTool(store: store, actions: actions)
        let update = UpdateCalendarEventTool(store: store, actions: actions)
        let delete = DeleteCalendarEventTool(store: store, actions: actions)
        let createArgs: JSONValue = .object(["title": .string("Interview Prep"), "start": .string("2026-09-26T15:00:00-04:00"), "end": .string("2026-09-26T16:00:00-04:00")])
        _ = try await create.execute(arguments: createArgs)
        guard let proposedCreate = actions.pendingAction else { throw CalendarHarnessError.failed("Create did not propose approval") }
        try require(fake.createCount == 0, "Create mutated before approval")
        actions.cancel(id: proposedCreate.id); try require(fake.createCount == 0 && actions.pendingAction == nil, "Cancel mutated Calendar")
        _ = try await create.execute(arguments: createArgs); let approvedCreate = actions.takeForApproval(id: actions.pendingAction!.id)!; _ = try store.perform(approvedCreate.calendarMutation)
        try require(fake.createCount == 1 && actions.takeForApproval(id: approvedCreate.id) == nil, "Approval was not exactly-once")
        let createdID = fake.fixtureEvents.last!.id
        _ = try await update.execute(arguments: .object(["event_reference": .string(createdID), "title": .string("Interview Prep Updated")]))
        let approvedUpdate = actions.takeForApproval(id: actions.pendingAction!.id)!; _ = try store.perform(approvedUpdate.calendarMutation)
        try require(fake.updateCount == 1 && fake.fixtureEvents.last?.title == "Interview Prep Updated", "Partial update failed")
        _ = try await delete.execute(arguments: .object(["event_reference": .string(createdID)])); let approvedDelete = actions.takeForApproval(id: actions.pendingAction!.id)!; _ = try store.perform(approvedDelete.calendarMutation)
        try require(fake.deleteCount == 1 && !fake.fixtureEvents.contains(where: { $0.id == createdID }), "Approved delete failed")
        do { _ = try await delete.execute(arguments: .object(["event_reference": .string("invented")])) ; throw CalendarHarnessError.failed("Invented reference was accepted") } catch CalendarMutationError.eventNotFound {}
        fake.recurringReferences.insert(events[0].id)
        do { _ = try await update.execute(arguments: .object(["event_reference": .string(events[0].id), "title": .string("Never mutate series")])) ; throw CalendarHarnessError.failed("Recurring event was proposed") } catch CalendarMutationError.recurringEventUnsupported {}
        try require(fake.updateCount == 1, "Recurring event mutation occurred")
        fake.recurringReferences.removeAll()
        do { _ = try await create.execute(arguments: .object(["title": .string(""), "start": .string("2026-09-26T16:00:00-04:00"), "end": .string("2026-09-26T15:00:00-04:00")])) ; throw CalendarHarnessError.failed("Invalid create was accepted") } catch is AgentToolError {}
        fake.mutationError = CalendarMutationError.saveFailed
        let failureAction = PendingAction(kind: .calendarCreate, summary: "Create Calendar Event", details: [], isDestructive: false, calendarMutation: .create(CalendarEventDraft(title: "Fails", startDate: tomorrowStart, endDate: tomorrowEnd, isAllDay: false, location: nil, notes: nil, calendarID: nil)))
        do { _ = try store.perform(failureAction.calendarMutation); throw CalendarHarnessError.failed("Write failure was swallowed") } catch CalendarMutationError.saveFailed {}
        fake.mutationError = nil
        print("PASS writes: proposal-only create, cancel, exactly-once approval, partial update, exact delete, invalid and failed writes")

        let privateTitle = "Arch Interview", privateLocation = "Private Office", privateQuery = "PRIVATE-CALENDAR-QUERY"
        let trace = TracingPolicy.toolInputs(name: "search_calendar_events", arguments: .object(["query": .string(privateQuery), "start": .string("2026-09-25T00:00:00-04:00"), "end": .string("2026-09-26T00:00:00-04:00")]))
        let traceOutput = TracingPolicy.toolOutput(name: "search_calendar_events", result: .object(result))
        let text = String(data: try JSONEncoder().encode(["input": trace, "output": traceOutput]), encoding: .utf8)!
        try require(!text.contains(privateTitle) && !text.contains(privateLocation) && !text.contains(privateQuery) && !text.contains("2026-09-25T"), "Calendar-private data leaked to trace metadata")
        try require(text.contains("range_hours") && text.contains("result_count"), "Safe calendar trace metrics absent")
        print("PASS privacy: event fields, query, timestamps, and raw result excluded")

        fake.fixtureEvents = events
        let runtime = AgentRuntime(client: CalendarToolClient(), tracer: NoOpTracer(), calendarStore: store)
        let answer = try await runtime.send(userMessage: "Find my Arch event.")
        try require(answer == "Your Arch Interview is at 2 PM.", "Calendar agent loop failed")
        print("PASS agent integration: registered Calendar tools complete the runtime loop")
        print("ALL CALENDAR TESTS PASSED")
    }
}
