import Foundation

/// Generic, explicit user approval boundary for external side effects.
enum PendingActionKind: String, Codable, Sendable {
    case calendarCreate, calendarUpdate, calendarDelete
}

struct PendingAction: Identifiable, Sendable {
    let id: UUID
    let kind: PendingActionKind
    let summary: String
    let details: [String]
    let isDestructive: Bool
    let createdAt: Date
    let expiresAt: Date
    let calendarMutation: CalendarMutation

    init(kind: PendingActionKind, summary: String, details: [String], isDestructive: Bool, calendarMutation: CalendarMutation, now: Date = Date()) {
        id = UUID(); self.kind = kind; self.summary = summary; self.details = details
        self.isDestructive = isDestructive; createdAt = now; expiresAt = now.addingTimeInterval(10 * 60)
        self.calendarMutation = calendarMutation
    }
}
