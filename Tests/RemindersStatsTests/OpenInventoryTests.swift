import Foundation
import XCTest
@testable import RemindersStats

final class OpenInventoryTests: XCTestCase {
    private let paris = TimeZone(identifier: "Europe/Paris")!

    /// Wednesday 12 Aug 2026 15:00 CEST
    private var now: Date { date(2026, 8, 12, 15, 0) }

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = paris
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func engine() -> StatsEngine {
        StatsEngine(calendar: calendar(), now: now)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = y
        parts.month = m
        parts.day = d
        parts.hour = h
        parts.minute = min
        parts.timeZone = paris
        return calendar().date(from: parts)!
    }

    func testSplitsOverdueFromOpenAndIgnoresCompleted() {
        let overdue = ReminderRecord(
            listName: "Work",
            isCompleted: false,
            completionDate: nil,
            due: .dateOnly(year: 2026, month: 8, day: 11),
            title: "File taxes"
        )
        let openToday = ReminderRecord(
            listName: "Work",
            isCompleted: false,
            completionDate: nil,
            due: .dateOnly(year: 2026, month: 8, day: 12),
            title: "Standup notes"
        )
        let undated = ReminderRecord(
            listName: "Work",
            isCompleted: false,
            completionDate: nil,
            due: nil,
            title: "Someday"
        )
        let done = ReminderRecord(
            listName: "Work",
            isCompleted: true,
            completionDate: date(2026, 8, 10, 9, 0),
            due: .timed(date(2026, 8, 10, 17, 0)),
            title: "Already done"
        )
        let otherList = ReminderRecord(
            listName: "Shopping",
            isCompleted: false,
            completionDate: nil,
            due: .dateOnly(year: 2026, month: 8, day: 1),
            title: "Milk"
        )

        let inventory = engine().openInventory(
            reminders: [overdue, openToday, undated, done, otherList],
            listNames: ["Work"]
        )

        XCTAssertEqual(inventory.overdue.map(\.title), ["File taxes"])
        XCTAssertEqual(inventory.open.map(\.title), ["Standup notes", "Someday"])
    }

    func testOverdueAreSortedOldestDueFirstAndOpenSoonestFirst() {
        let older = ReminderRecord(
            listName: "Work",
            isCompleted: false,
            completionDate: nil,
            due: .dateOnly(year: 2026, month: 8, day: 1),
            title: "Oldest"
        )
        let newer = ReminderRecord(
            listName: "Work",
            isCompleted: false,
            completionDate: nil,
            due: .dateOnly(year: 2026, month: 8, day: 10),
            title: "Newer overdue"
        )
        let later = ReminderRecord(
            listName: "Work",
            isCompleted: false,
            completionDate: nil,
            due: .timed(date(2026, 8, 20, 9, 0)),
            title: "Later"
        )
        let sooner = ReminderRecord(
            listName: "Work",
            isCompleted: false,
            completionDate: nil,
            due: .timed(date(2026, 8, 13, 9, 0)),
            title: "Sooner"
        )
        let undated = ReminderRecord(
            listName: "Work",
            isCompleted: false,
            completionDate: nil,
            due: nil,
            title: "No date"
        )

        let inventory = engine().openInventory(
            reminders: [newer, older, later, undated, sooner],
            listNames: ["Work"]
        )
        XCTAssertEqual(inventory.overdue.map(\.title), ["Oldest", "Newer overdue"])
        XCTAssertEqual(inventory.open.map(\.title), ["Sooner", "Later", "No date"])
    }

    func testEmptyTitleBecomesUntitled() {
        let reminder = ReminderRecord(
            listName: "Work",
            isCompleted: false,
            completionDate: nil,
            due: .dateOnly(year: 2026, month: 8, day: 1),
            title: "   "
        )
        let inventory = engine().openInventory(reminders: [reminder], listNames: ["Work"])
        XCTAssertEqual(inventory.overdue.first?.title, "(untitled)")
    }
}
