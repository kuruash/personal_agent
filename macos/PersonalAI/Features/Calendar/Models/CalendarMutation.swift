import Foundation

struct CalendarEventDraft: Codable, Equatable, Sendable {
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let calendarID: String?
}

struct CalendarEventUpdate: Codable, Equatable, Sendable {
    let eventReference: String
    let title: String?
    let startDate: Date?
    let endDate: Date?
    let isAllDay: Bool?
    let location: String?
    let notes: String?
}

struct CalendarEventDeletion: Codable, Equatable, Sendable { let eventReference: String }

enum CalendarMutation: Sendable {
    case create(CalendarEventDraft)
    case update(CalendarEventUpdate)
    case delete(CalendarEventDeletion)
}

enum CalendarMutationError: LocalizedError {
    case unauthorized, unavailableCalendar, readOnlyCalendar, eventNotFound, recurringEventUnsupported, invalidMutation, saveFailed
    var errorDescription: String? {
        switch self {
        case .unauthorized: "Calendar write access is unavailable."
        case .unavailableCalendar: "The selected calendar is unavailable."
        case .readOnlyCalendar: "The selected calendar cannot be changed."
        case .eventNotFound: "That calendar event no longer exists."
        case .recurringEventUnsupported: "Changing recurring events is not supported yet."
        case .invalidMutation: "The proposed calendar change is invalid."
        case .saveFailed: "Calendar could not save that change."
        }
    }
}
