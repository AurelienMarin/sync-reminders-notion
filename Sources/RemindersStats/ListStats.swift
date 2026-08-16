import Foundation

struct ListStats: Equatable, Sendable {
    var listName: String
    var onTimeCount: Int
    var lateCount: Int
    var datedCompletionCount: Int
    var onTimePercent: Double?
    var latePercent: Double?
    var openOverdueCount: Int
    var completedThisWeek: Int
    var completedThisMonth: Int
    var meanEarlySeconds: TimeInterval?

    var formattedAverage: String {
        Self.formatAverage(meanEarlySeconds)
    }

    static func formatAverage(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "n/a" }
        let adverb = seconds >= 0 ? "early" : "late"
        let absolute = abs(seconds)
        if absolute < 24 * 3600 {
            let hours = absolute / 3600
            return "\(formatNumber(hours)) \(hours == 1 ? "hour" : "hours") \(adverb)"
        }
        let days = absolute / 86_400
        return "\(formatNumber(days)) \(days == 1 ? "day" : "days") \(adverb)"
    }

    private static func formatNumber(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded(.towardZero) {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}

struct OpenReminder: Equatable, Sendable {
    var title: String
    var listName: String
    var due: ReminderRecord.Due?
}

struct OpenInventory: Equatable, Sendable {
    var overdue: [OpenReminder]
    var open: [OpenReminder]
}

struct DashboardStats: Equatable, Sendable {
    var overall: ListStats
    var byList: [ListStats]
}
