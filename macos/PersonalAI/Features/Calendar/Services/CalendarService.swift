import EventKit
import Foundation
import os

@MainActor
protocol CalendarServicing: AnyObject {
    func authorizationStatus() -> CalendarAuthorizationStatus
    func requestAccess() async throws -> CalendarAuthorizationStatus
    func calendarCount() -> Int
    func events(from start: Date, to end: Date) throws -> [CalendarEvent]
    func event(reference: String) throws -> CalendarEvent
    func createEvent(_ draft: CalendarEventDraft) throws -> CalendarEvent
    func updateEvent(_ update: CalendarEventUpdate) throws -> CalendarEvent
    func deleteEvent(_ deletion: CalendarEventDeletion) throws
    func validate(_ mutation: CalendarMutation) throws
}

@MainActor
final class EventKitCalendarService: CalendarServicing {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.personalai.app",
        category: "CalendarService"
    )
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func authorizationStatus() -> CalendarAuthorizationStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .authorized
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .writeOnly: .unavailable
        @unknown default: .unavailable
        }
    }

    func requestAccess() async throws -> CalendarAuthorizationStatus {
        guard authorizationStatus() == .notDetermined else { return authorizationStatus() }
        #if DEBUG
        Self.logger.debug("CalendarService EventKit request started")
        #endif
        do {
            _ = try await eventStore.requestFullAccessToEvents()
            #if DEBUG
            Self.logger.debug("EventKit request returned")
            #endif
        } catch {
            #if DEBUG
            Self.logger.error("EventKit Calendar request failed: \(error.localizedDescription, privacy: .private)")
            #endif
            throw error
        }
        let status = authorizationStatus()
        #if DEBUG
        Self.logger.debug("Authorization after request: \(status.rawValue, privacy: .public)")
        #endif
        return status
    }

    func calendarCount() -> Int {
        guard authorizationStatus() == .authorized else { return 0 }
        return eventStore.calendars(for: .event).count
    }

    func events(from start: Date, to end: Date) throws -> [CalendarEvent] {
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        return eventStore.events(matching: predicate).map { event in
            CalendarEvent(
                id: event.eventIdentifier ?? event.calendarItemIdentifier,
                title: event.title ?? "Untitled event",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                calendarName: event.calendar.title,
                location: event.location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )
        }
    }

    func event(reference: String) throws -> CalendarEvent {
        guard let event = eventStore.event(withIdentifier: reference) else { throw CalendarMutationError.eventNotFound }
        return model(event)
    }

    func createEvent(_ draft: CalendarEventDraft) throws -> CalendarEvent {
        try requireWriteAccess()
        let event = EKEvent(eventStore: eventStore)
        event.title = draft.title; event.startDate = draft.startDate; event.endDate = draft.endDate
        event.isAllDay = draft.isAllDay; event.location = draft.location; event.notes = draft.notes
        let calendar = try writableCalendar(id: draft.calendarID)
        event.calendar = calendar
        do { try eventStore.save(event, span: .thisEvent); return model(event) }
        catch { log(error); throw CalendarMutationError.saveFailed }
    }

    func updateEvent(_ update: CalendarEventUpdate) throws -> CalendarEvent {
        try requireWriteAccess()
        guard let event = eventStore.event(withIdentifier: update.eventReference) else { throw CalendarMutationError.eventNotFound }
        try requireMutable(event)
        if let title = update.title { event.title = title }
        if let start = update.startDate { event.startDate = start }
        if let end = update.endDate { event.endDate = end }
        if let allDay = update.isAllDay { event.isAllDay = allDay }
        if let location = update.location { event.location = location }
        if let notes = update.notes { event.notes = notes }
        guard event.endDate > event.startDate else { throw CalendarMutationError.invalidMutation }
        do { try eventStore.save(event, span: .thisEvent); return model(event) }
        catch { log(error); throw CalendarMutationError.saveFailed }
    }

    func deleteEvent(_ deletion: CalendarEventDeletion) throws {
        try requireWriteAccess()
        guard let event = eventStore.event(withIdentifier: deletion.eventReference) else { throw CalendarMutationError.eventNotFound }
        try requireMutable(event)
        do { try eventStore.remove(event, span: .thisEvent) }
        catch { log(error); throw CalendarMutationError.saveFailed }
    }

    func validate(_ mutation: CalendarMutation) throws {
        try requireWriteAccess()
        switch mutation {
        case .create(let draft): _ = try writableCalendar(id: draft.calendarID)
        case .update(let update):
            guard let event = eventStore.event(withIdentifier: update.eventReference) else { throw CalendarMutationError.eventNotFound }
            try requireMutable(event)
            if let start = update.startDate, let end = update.endDate, end <= start { throw CalendarMutationError.invalidMutation }
        case .delete(let deletion):
            guard let event = eventStore.event(withIdentifier: deletion.eventReference) else { throw CalendarMutationError.eventNotFound }
            try requireMutable(event)
        }
    }

    private func requireWriteAccess() throws {
        guard authorizationStatus() == .authorized else { throw CalendarMutationError.unauthorized }
    }

    private func writableCalendar(id: String?) throws -> EKCalendar {
        let calendar: EKCalendar?
        if let id { calendar = eventStore.calendar(withIdentifier: id) }
        else { calendar = eventStore.defaultCalendarForNewEvents }
        guard let calendar else { throw CalendarMutationError.unavailableCalendar }
        guard calendar.allowsContentModifications else { throw CalendarMutationError.readOnlyCalendar }
        return calendar
    }

    private func requireMutable(_ event: EKEvent) throws {
        guard event.calendar.allowsContentModifications else { throw CalendarMutationError.readOnlyCalendar }
        // V2 deliberately supports only one non-recurring occurrence; never widen scope.
        guard event.recurrenceRules?.isEmpty != false else { throw CalendarMutationError.recurringEventUnsupported }
    }

    private func model(_ event: EKEvent) -> CalendarEvent {
        CalendarEvent(id: event.eventIdentifier ?? event.calendarItemIdentifier, title: event.title ?? "Untitled event", startDate: event.startDate, endDate: event.endDate, isAllDay: event.isAllDay, calendarName: event.calendar.title, location: event.location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
    }

    private func log(_ error: Error) {
        #if DEBUG
        Self.logger.error("EventKit mutation failed: \(error.localizedDescription, privacy: .private)")
        #endif
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
