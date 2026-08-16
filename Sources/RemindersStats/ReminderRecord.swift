import Foundation

public struct ReminderRecord: Equatable, Sendable {
    public var listName: String
    public var isCompleted: Bool
    public var completionDate: Date?
    public var due: Due?
    public var title: String

    public init(listName: String, isCompleted: Bool, completionDate: Date?, due: Due?, title: String = "") {
        self.listName = listName
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.due = due
        self.title = title
    }

    public enum Due: Equatable, Sendable {
        case dateOnly(year: Int, month: Int, day: Int)
        case timed(Date)

        /// All-day when hour and minute are missing or both 0 (Reminders stores date-only as 00:00).
        public static func from(components: DateComponents, calendar: Calendar) -> Due? {
            guard let year = components.year, let month = components.month, let day = components.day else {
                return nil
            }
            let hour = components.hour
            let minute = components.minute
            let isDateOnly = (hour == nil && minute == nil) || (hour == 0 && (minute ?? 0) == 0)
            if isDateOnly {
                return .dateOnly(year: year, month: month, day: day)
            }
            guard let date = calendar.date(from: components) else {
                return nil
            }
            return .timed(date)
        }
    }
}
