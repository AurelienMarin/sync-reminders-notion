import Foundation

public struct StatsEngine: Sendable {
    public var calendar: Calendar
    public var now: Date

    public init(calendar: Calendar = .current, now: Date = Date()) {
        self.calendar = calendar
        self.now = now
    }

    public func compute(reminders: [ReminderRecord], listNames: [String]) -> DashboardStats {
        let allowed = Set(listNames)
        let included = reminders.filter { allowed.contains($0.listName) }
        let overall = stats(for: included, name: "Overall")
        let byList = listNames.map { name in
            stats(for: included.filter { $0.listName == name }, name: name)
        }
        return DashboardStats(overall: overall, byList: byList)
    }

    public func openInventory(reminders: [ReminderRecord], listNames: [String]) -> OpenInventory {
        let allowed = Set(listNames)
        var overdue: [OpenReminder] = []
        var open: [OpenReminder] = []
        for reminder in reminders where allowed.contains(reminder.listName) {
            if reminder.effectiveCompletionDate != nil { continue }
            let item = OpenReminder(
                title: displayTitle(reminder.title),
                listName: reminder.listName,
                due: reminder.due
            )
            if isOverdue(due: reminder.due) {
                overdue.append(item)
            } else {
                open.append(item)
            }
        }
        overdue.sort { dueSortKey($0.due) < dueSortKey($1.due) }
        open.sort { lhs, rhs in
            switch (lhs.due, rhs.due) {
            case (nil, nil): return lhs.title < rhs.title
            case (nil, _): return false
            case (_, nil): return true
            default: return dueSortKey(lhs.due) < dueSortKey(rhs.due)
            }
        }
        return OpenInventory(overdue: overdue, open: open)
    }

    private func displayTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(untitled)" : trimmed
    }

    private func dueSortKey(_ due: ReminderRecord.Due?) -> Date {
        switch due {
        case let .timed(date):
            return date
        case let .dateOnly(year, month, day):
            var parts = DateComponents()
            parts.year = year
            parts.month = month
            parts.day = day
            return calendar.date(from: parts) ?? .distantFuture
        case nil:
            return .distantFuture
        }
    }

    private func stats(for reminders: [ReminderRecord], name: String) -> ListStats {
        var onTime = 0
        var late = 0
        var openOverdue = 0
        var week = 0
        var month = 0
        var deltas: [TimeInterval] = []

        for reminder in reminders {
            if let completed = reminder.effectiveCompletionDate {
                if calendar.isDate(completed, equalTo: now, toGranularity: .weekOfYear) {
                    week += 1
                }
                if calendar.isDate(completed, equalTo: now, toGranularity: .month) {
                    month += 1
                }
                if let due = reminder.due {
                    if isOnTime(completion: completed, due: due) {
                        onTime += 1
                    } else {
                        late += 1
                    }
                    deltas.append(earlySeconds(completion: completed, due: due))
                }
            } else if isOverdue(due: reminder.due) {
                openOverdue += 1
            }
        }

        let dated = onTime + late
        return ListStats(
            listName: name,
            onTimeCount: onTime,
            lateCount: late,
            datedCompletionCount: dated,
            onTimePercent: dated == 0 ? nil : Double(onTime) / Double(dated) * 100,
            latePercent: dated == 0 ? nil : Double(late) / Double(dated) * 100,
            openOverdueCount: openOverdue,
            completedThisWeek: week,
            completedThisMonth: month,
            meanEarlySeconds: deltas.isEmpty ? nil : deltas.reduce(0, +) / Double(deltas.count)
        )
    }

    private func isOnTime(completion: Date, due: ReminderRecord.Due) -> Bool {
        switch due {
        case let .timed(deadline):
            return completion <= deadline
        case let .dateOnly(year, month, day):
            return compare(ymd(completion), (year, month, day)) != .orderedDescending
        }
    }

    private func isOverdue(due: ReminderRecord.Due?) -> Bool {
        guard let due else { return false }
        switch due {
        case let .timed(deadline):
            return now > deadline
        case let .dateOnly(year, month, day):
            return compare(ymd(now), (year, month, day)) == .orderedDescending
        }
    }

    private func earlySeconds(completion: Date, due: ReminderRecord.Due) -> TimeInterval {
        switch due {
        case let .timed(deadline):
            return deadline.timeIntervalSince(completion)
        case let .dateOnly(year, month, day):
            var parts = DateComponents()
            parts.year = year
            parts.month = month
            parts.day = day
            let dueDay = calendar.startOfDay(for: calendar.date(from: parts) ?? completion)
            let completionDay = calendar.startOfDay(for: completion)
            let days = calendar.dateComponents([.day], from: completionDay, to: dueDay).day ?? 0
            return Double(days) * 86_400
        }
    }

    private func ymd(_ date: Date) -> (Int, Int, Int) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func compare(_ lhs: (Int, Int, Int), _ rhs: (Int, Int, Int)) -> ComparisonResult {
        if lhs.0 != rhs.0 { return lhs.0 < rhs.0 ? .orderedAscending : .orderedDescending }
        if lhs.1 != rhs.1 { return lhs.1 < rhs.1 ? .orderedAscending : .orderedDescending }
        if lhs.2 != rhs.2 { return lhs.2 < rhs.2 ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }
}

private extension ReminderRecord {
    var effectiveCompletionDate: Date? {
        guard isCompleted, let completionDate else { return nil }
        return completionDate
    }
}
