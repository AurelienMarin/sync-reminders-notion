import Foundation

public struct ListStats: Equatable, Sendable {
    public var listName: String
    public var onTimeCount: Int
    public var lateCount: Int
    public var datedCompletionCount: Int
    public var onTimePercent: Double?
    public var latePercent: Double?
    public var openOverdueCount: Int
    public var completedThisWeek: Int
    public var completedThisMonth: Int
    public var meanEarlySeconds: TimeInterval?

    public init(
        listName: String,
        onTimeCount: Int,
        lateCount: Int,
        datedCompletionCount: Int,
        onTimePercent: Double?,
        latePercent: Double?,
        openOverdueCount: Int,
        completedThisWeek: Int,
        completedThisMonth: Int,
        meanEarlySeconds: TimeInterval?
    ) {
        self.listName = listName
        self.onTimeCount = onTimeCount
        self.lateCount = lateCount
        self.datedCompletionCount = datedCompletionCount
        self.onTimePercent = onTimePercent
        self.latePercent = latePercent
        self.openOverdueCount = openOverdueCount
        self.completedThisWeek = completedThisWeek
        self.completedThisMonth = completedThisMonth
        self.meanEarlySeconds = meanEarlySeconds
    }

    public var formattedAverage: String {
        Self.formatAverage(meanEarlySeconds)
    }

    public static func formatAverage(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "n/a" }
        let adverb = seconds >= 0 ? "early" : "late"
        let absolute = abs(seconds)
        if absolute < 24 * 3600 {
            let hours = absolute / 3600
            return "\(Self.formatNumber(hours)) \(hours == 1 ? "hour" : "hours") \(adverb)"
        }
        let days = absolute / 86_400
        return "\(Self.formatNumber(days)) \(days == 1 ? "day" : "days") \(adverb)"
    }

    private static func formatNumber(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded(.towardZero) {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}

public struct OpenReminder: Equatable, Sendable {
    public var title: String
    public var listName: String
    public var due: ReminderRecord.Due?

    public init(title: String, listName: String, due: ReminderRecord.Due?) {
        self.title = title
        self.listName = listName
        self.due = due
    }
}

public struct OpenInventory: Equatable, Sendable {
    public var overdue: [OpenReminder]
    public var open: [OpenReminder]

    public init(overdue: [OpenReminder], open: [OpenReminder]) {
        self.overdue = overdue
        self.open = open
    }
}

public struct DashboardStats: Equatable, Sendable {
    public var overall: ListStats
    public var byList: [ListStats]

    public init(overall: ListStats, byList: [ListStats]) {
        self.overall = overall
        self.byList = byList
    }
}
