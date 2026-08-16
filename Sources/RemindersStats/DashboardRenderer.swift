import Foundation

public enum DashboardRenderer {
    public static func text(stats: DashboardStats, updatedAt: Date, timeZone: TimeZone) -> String {
        var lines: [String] = []
        lines.append("Last updated: \(formatTimestamp(updatedAt, timeZone: timeZone))")
        lines.append("")
        lines.append(contentsOf: section(stats.overall, heading: "Overall"))
        if !stats.byList.isEmpty {
            lines.append("")
            lines.append("By list")
            for list in stats.byList {
                lines.append("")
                lines.append(contentsOf: section(list, heading: list.listName))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func blocks(
        stats: DashboardStats,
        updatedAt: Date,
        timeZone: TimeZone,
        inventory: OpenInventory = OpenInventory(overdue: [], open: [])
    ) -> [NotionBlock] {
        var blocks: [NotionBlock] = [
            .paragraph([
                RichTextSpan(
                    text: "Last updated: \(formatTimestamp(updatedAt, timeZone: timeZone))",
                    italic: true,
                    color: "gray"
                ),
            ]),
            .heading2("Overall"),
            kpiColumns(stats.overall),
            secondaryColumns(stats.overall),
        ]
        if !stats.byList.isEmpty {
            blocks.append(.divider)
            blocks.append(.heading2("By list"))
            blocks.append(listTable(stats.byList))
        }
        blocks.append(.divider)
        blocks.append(.paragraph([
            RichTextSpan(
                text: "Read-only snapshot from Apple Reminders. Mark items done in Reminders — status here cannot be changed.",
                italic: true,
                color: "gray"
            ),
        ]))
        blocks.append(.heading2("Overdue"))
        blocks.append(contentsOf: itemBlocks(inventory.overdue, status: "Overdue", timeZone: timeZone))
        blocks.append(.heading2("Open"))
        blocks.append(contentsOf: itemBlocks(inventory.open, status: "Open", timeZone: timeZone))
        return blocks
    }

    private static func section(_ stats: ListStats, heading: String) -> [String] {
        [heading] + metricLines(stats)
    }

    private static func metricLines(_ stats: ListStats) -> [String] {
        let onTime: String
        if let percent = stats.onTimePercent {
            onTime = pad("On time", stats.onTimeCount) + "  (\(formatPercent(percent))% of dated completions)"
        } else {
            onTime = pad("On time", stats.onTimeCount)
        }
        let late: String
        if let percent = stats.latePercent {
            late = pad("Late", stats.lateCount) + "  (\(formatPercent(percent))%)"
        } else {
            late = pad("Late", stats.lateCount)
        }
        return [
            onTime,
            late,
            pad("Open overdue", stats.openOverdueCount),
            pad("Done this week", stats.completedThisWeek),
            pad("Done this month", stats.completedThisMonth),
            padLabel("Average") + stats.formattedAverage,
        ]
    }

    private static func kpiColumns(_ stats: ListStats) -> NotionBlock {
        .columnList([
            [metricCard(
                headline: percentOrNA(stats.onTimePercent),
                caption: datedCaption("On time", count: stats.onTimeCount, dated: stats.datedCompletionCount),
                emoji: "✅",
                color: "green_background"
            )],
            [metricCard(
                headline: percentOrNA(stats.latePercent),
                caption: datedCaption("Late", count: stats.lateCount, dated: stats.datedCompletionCount),
                emoji: "⏰",
                color: "orange_background"
            )],
            [metricCard(
                headline: "\(stats.openOverdueCount)",
                caption: "Open overdue",
                emoji: "⚠️",
                color: stats.openOverdueCount == 0 ? "gray_background" : "red_background"
            )],
            [metricCard(
                headline: "\(stats.completedThisWeek)",
                caption: "This week",
                emoji: "📅",
                color: "blue_background"
            )],
        ])
    }

    private static func secondaryColumns(_ stats: ListStats) -> NotionBlock {
        .columnList([
            [metricCard(
                headline: stats.formattedAverage,
                caption: "Average",
                emoji: "⏱️",
                color: "purple_background"
            )],
            [metricCard(
                headline: "\(stats.completedThisMonth)",
                caption: "This month",
                emoji: "📈",
                color: "gray_background"
            )],
        ])
    }

    private static func metricCard(headline: String, caption: String, emoji: String, color: String) -> NotionBlock {
        .metricCallout(
            spans: [
                RichTextSpan(text: headline + "\n", bold: true),
                RichTextSpan(text: caption, color: "gray"),
            ],
            emoji: emoji,
            color: color
        )
    }

    private static func listTable(_ lists: [ListStats]) -> NotionBlock {
        let header: [[RichTextSpan]] = ["List", "On time", "Late", "Overdue", "Week", "Month", "Avg"].map {
            [RichTextSpan(text: $0, bold: true)]
        }
        let rows = lists.map { list -> [[RichTextSpan]] in
            [
                [RichTextSpan(text: list.listName, bold: true)],
                [RichTextSpan(text: countAndPercent(list.onTimeCount, list.onTimePercent))],
                [RichTextSpan(text: countAndPercent(list.lateCount, list.latePercent))],
                [RichTextSpan(text: "\(list.openOverdueCount)")],
                [RichTextSpan(text: "\(list.completedThisWeek)")],
                [RichTextSpan(text: "\(list.completedThisMonth)")],
                [RichTextSpan(text: list.formattedAverage)],
            ]
        }
        return .table(width: 7, hasColumnHeader: true, hasRowHeader: true, rows: [header] + rows)
    }

    private static func percentOrNA(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return "\(formatPercent(value))%"
    }

    private static func datedCaption(_ label: String, count: Int, dated: Int) -> String {
        if dated == 0 { return "\(label) · no dated completions" }
        return "\(label) · \(count) of \(dated)"
    }

    private static let itemLimit = 50

    private static func itemBlocks(
        _ items: [OpenReminder],
        status: String,
        timeZone: TimeZone
    ) -> [NotionBlock] {
        if items.isEmpty {
            return [.paragraph([RichTextSpan(text: "None", italic: true, color: "gray")])]
        }
        let header: [[RichTextSpan]] = ["Reminder", "List", "Due", "Status"].map {
            [RichTextSpan(text: $0, bold: true)]
        }
        let shown = items.prefix(itemLimit)
        let rows: [[[RichTextSpan]]] = shown.map { item in
            [
                [RichTextSpan(text: item.title)],
                [RichTextSpan(text: item.listName, color: "gray")],
                [RichTextSpan(text: formatDue(item.due, timeZone: timeZone))],
                [RichTextSpan(text: status, bold: true, color: status == "Overdue" ? "red" : "gray")],
            ]
        }
        var blocks: [NotionBlock] = [
            .table(width: 4, hasColumnHeader: true, hasRowHeader: false, rows: [header] + rows),
        ]
        if items.count > itemLimit {
            blocks.append(.paragraph([
                RichTextSpan(
                    text: "Showing \(itemLimit) of \(items.count).",
                    italic: true,
                    color: "gray"
                ),
            ]))
        }
        return blocks
    }

    private static func formatDue(_ due: ReminderRecord.Due?, timeZone: TimeZone) -> String {
        switch due {
        case nil:
            return "No due date"
        case let .dateOnly(year, month, day):
            var parts = DateComponents()
            parts.year = year
            parts.month = month
            parts.day = day
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            guard let date = calendar.date(from: parts) else { return "No due date" }
            return formatDay(date, timeZone: timeZone)
        case let .timed(date):
            return formatDayTime(date, timeZone: timeZone)
        }
    }

    private static func formatDay(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    private static func formatDayTime(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter.string(from: date)
    }

    private static func countAndPercent(_ count: Int, _ percent: Double?) -> String {
        if let percent {
            return "\(count) (\(formatPercent(percent))%)"
        }
        return "\(count)"
    }

    private static func pad(_ label: String, _ value: Int) -> String {
        padLabel(label) + String(value)
    }

    private static func padLabel(_ label: String) -> String {
        "  " + label.padding(toLength: 16, withPad: " ", startingAt: 0)
    }

    private static func formatPercent(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    private static func formatTimestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        let zone = timeZone.identifier
        return "\(formatter.string(from: date)) (\(zone))"
    }
}

public struct RichTextSpan: Equatable, Sendable {
    public var text: String
    public var bold: Bool
    public var italic: Bool
    public var color: String
    public var link: String?

    public init(
        text: String,
        bold: Bool = false,
        italic: Bool = false,
        color: String = "default",
        link: String? = nil
    ) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.color = color
        self.link = link
    }
}

public enum NotionBlock: Equatable, Sendable {
    case heading2(String)
    case heading3(String)
    case callout(String)
    case bulleted(String)
    case paragraph([RichTextSpan])
    case metricCallout(spans: [RichTextSpan], emoji: String, color: String)
    case divider
    case columnList([[NotionBlock]])
    case table(width: Int, hasColumnHeader: Bool, hasRowHeader: Bool, rows: [[[RichTextSpan]]])
}
