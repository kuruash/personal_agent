import Combine
import Foundation
import os

@MainActor
final class CalendarStore: ObservableObject, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.personalai.app",
        category: "CalendarStore"
    )
    @Published private(set) var authorizationStatus: CalendarAuthorizationStatus
    @Published private(set) var calendarCount = 0
    @Published private(set) var permissionErrorMessage: String?
    @Published private(set) var isRequestingAccess = false

    private let service: any CalendarServicing

    init(service: (any CalendarServicing)? = nil) {
        let resolvedService = service ?? EventKitCalendarService()
        self.service = resolvedService
        self.authorizationStatus = resolvedService.authorizationStatus()
        self.permissionErrorMessage = nil
        refreshStatus()
    }

    func refreshStatus() {
        authorizationStatus = service.authorizationStatus()
        calendarCount = service.calendarCount()
    }

    func connect() async {
        guard !isRequestingAccess else { return }
        #if DEBUG
        Self.logger.debug("CalendarStore request access started")
        #endif
        isRequestingAccess = true
        permissionErrorMessage = nil
        defer { isRequestingAccess = false }
        do {
            _ = try await service.requestAccess()
        } catch {
            #if DEBUG
            Self.logger.error("Calendar permission request failed: \(error.localizedDescription, privacy: .private)")
            #endif
            permissionErrorMessage = "Calendar permission could not be requested."
        }
        // Never infer access from EventKit's request result. Re-read the authoritative status.
        refreshStatus()
        #if DEBUG
        Self.logger.debug("CalendarStore authorization after request: \(self.authorizationStatus.rawValue, privacy: .public)")
        #endif
    }

    func events(from start: Date, to end: Date) throws -> [CalendarEvent] {
        let values = try service.events(from: start, to: end)
        return values.sorted(by: CalendarEvent.deterministicOrder)
    }

    func event(reference: String) throws -> CalendarEvent { try service.event(reference: reference) }

    func validate(_ mutation: CalendarMutation) throws { try service.validate(mutation) }

    func perform(_ mutation: CalendarMutation) throws -> CalendarEvent? {
        refreshStatus()
        guard authorizationStatus == .authorized else { throw CalendarMutationError.unauthorized }
        switch mutation {
        case .create(let draft): return try service.createEvent(draft)
        case .update(let update): return try service.updateEvent(update)
        case .delete(let deletion): try service.deleteEvent(deletion); return nil
        }
    }
}
