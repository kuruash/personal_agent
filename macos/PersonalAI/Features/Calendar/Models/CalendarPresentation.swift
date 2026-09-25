import Foundation

enum CalendarPresentation {
    static func dateRange(start: Date, end: Date, allDay: Bool) -> String {
        if allDay { return "All day" }
        let formatter = DateIntervalFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: start, to: end)
    }
}
