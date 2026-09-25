import Foundation

/// The small, read-only calendar representation shared by views and agent tools.
struct CalendarEvent: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarName: String
    let location: String?

    static func deterministicOrder(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
        if lhs.endDate != rhs.endDate { return lhs.endDate < rhs.endDate }
        if lhs.id != rhs.id { return lhs.id < rhs.id }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

enum CalendarRangeRelationship: String, Codable, Equatable, Sendable {
    case startsWithinRange = "starts_within_range"
    case continuesIntoRange = "continues_into_range"
    case spansEntireRange = "spans_entire_range"

    static func classify(event: CalendarEvent, rangeStart: Date, rangeEnd: Date) -> Self {
        // An all-day event beginning on the requested local calendar day has a start
        // at that day's boundary and is therefore a normal event for that day.
        if event.startDate >= rangeStart && event.startDate < rangeEnd {
            return .startsWithinRange
        }
        if event.startDate < rangeStart && event.endDate > rangeEnd {
            return .spansEntireRange
        }
        return .continuesIntoRange
    }
}

enum CalendarAuthorizationStatus: String, Codable, Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable
}

enum CalendarStoreError: Error {
    case queryFailed
}
