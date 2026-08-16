import Foundation
import XCTest
@testable import RemindersStats

final class StatsEngineTests: XCTestCase {
    private let paris = TimeZone(identifier: "Europe/Paris")!

    /// Wednesday 12 Aug 2026 15:00 CEST. ISO week Mon 10 – Sun 16 Aug. August calendar month.
    private var now: Date {
        date(2026, 8, 12, 15, 0)
    }

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

    func testTimedCompletionExactlyAtDueIsOnTime() {
        let reminder = ReminderRecord(
            listName: "Work",
            isCompleted: true,
            completionDate: date(2026, 8, 11, 17, 0),
            due: .timed(date(2026, 8, 11, 17, 0))
        )
        let stats = engine().compute(reminders: [reminder], listNames: ["Work"])
        XCTAssertEqual(stats.overall.onTimeCount, 1)
        XCTAssertEqual(stats.overall.lateCount, 0)
        XCTAssertEqual(stats.overall.onTimePercent, 100)
    }

    func testTimedCompletionAfterDueIsLate() {
        let reminder = ReminderRecord(
            listName: "Work",
            isCompleted: true,
            completionDate: date(2026, 8, 11, 17, 1),
            due: .timed(date(2026, 8, 11, 17, 0))
        )
        let stats = engine().compute(reminders: [reminder], listNames: ["Work"])
        XCTAssertEqual(stats.overall.onTimeCount, 0)
        XCTAssertEqual(stats.overall.lateCount, 1)
        XCTAssertEqual(stats.overall.latePercent, 100)
    }

    func testDateOnlyCompletedLateEveningSameDayIsOnTime() {
        let reminder = ReminderRecord(
            listName: "Work",
            isCompleted: true,
            completionDate: date(2026, 8, 11, 22, 0),
            due: .dateOnly(year: 2026, month: 8, day: 11)
        )
        let stats = engine().compute(reminders: [reminder], listNames: ["Work"])
        XCTAssertEqual(stats.overall.onTimeCount, 1)
        XCTAssertEqual(stats.overall.lateCount, 0)
    }

    func testDateOnlyCompletedNextCalendarDayIsLate() {
        let reminder = ReminderRecord(
            listName: "Work",
            isCompleted: true,
            completionDate: date(2026, 8, 12, 0, 1),
            due: .dateOnly(year: 2026, month: 8, day: 11)
        )
        let stats = engine().compute(reminders: [reminder], listNames: ["Work"])
        XCTAssertEqual(stats.overall.onTimeCount, 0)
        XCTAssertEqual(stats.overall.lateCount, 1)
    }

    func testDateOnlyOpenOnDueDayIsNotOverdue() {
        let reminder = ReminderRecord(
            listName: "Work",
            isCompleted: false,
            completionDate: nil,
            due: .dateOnly(year: 2026, month: 8, day: 12)
        )
        let stats = engine().compute(reminders: [reminder], listNames: ["Work"])
        XCTAssertEqual(stats.overall.openOverdueCount, 0)
    }

    func testDateOnlyOpenAfterDueDayIsOverdue() {
        let reminder = ReminderRecord(
            listName: "Work",
            isCompleted: false,
            completionDate: nil,
            due: .dateOnly(year: 2026, month: 8, day: 11)
        )
        let stats = engine().compute(reminders: [reminder], listNames: ["Work"])
        XCTAssertEqual(stats.overall.openOverdueCount, 1)
    }

    func testTimedOpenAfterDueInstantIsOverdue() {
        let reminder = ReminderRecord(
            listName: "Work",
            isCompleted: false,
            completionDate: nil,
            due: .timed(date(2026, 8, 12, 14, 59))
        )
        let stats = engine().compute(reminders: [reminder], listNames: ["Work"])
        XCTAssertEqual(stats.overall.openOverdueCount, 1)
    }

    func testUndatedCompletedCountsTowardVolumeNotPunctuality() {
        let reminder = ReminderRecord(
            listName: "Work",
            isCompleted: true,
            completionDate: date(2026, 8, 11, 10, 0),
            due: nil
        )
        let stats = engine().compute(reminders: [reminder], listNames: ["Work"])
        XCTAssertEqual(stats.overall.onTimeCount, 0)
        XCTAssertEqual(stats.overall.lateCount, 0)
        XCTAssertEqual(stats.overall.datedCompletionCount, 0)
        XCTAssertNil(stats.overall.onTimePercent)
        XCTAssertEqual(stats.overall.completedThisWeek, 1)
        XCTAssertEqual(stats.overall.completedThisMonth, 1)
        XCTAssertNil(stats.overall.meanEarlySeconds)
        XCTAssertEqual(stats.overall.formattedAverage, "n/a")
    }

    func testVolumeExcludesCompletionsOutsideCurrentWeekAndMonth() {
        let thisWeek = ReminderRecord(
            listName: "Work",
            isCompleted: true,
            completionDate: date(2026, 8, 10, 0, 0),
            due: nil
        )
        let lastWeek = ReminderRecord(
            listName: "Work",
            isCompleted: true,
            completionDate: date(2026, 8, 9, 23, 59),
            due: nil
        )
        let lastMonth = ReminderRecord(
            listName: "Work",
            isCompleted: true,
            completionDate: date(2026, 7, 31, 23, 59),
            due: nil
        )
        let stats = engine().compute(reminders: [thisWeek, lastWeek, lastMonth], listNames: ["Work"])
        XCTAssertEqual(stats.overall.completedThisWeek, 1)
        XCTAssertEqual(stats.overall.completedThisMonth, 2)
    }

    func testAverageUsesTimedHoursAndDateOnlyWholeDays() {
        let twoHoursEarly = ReminderRecord(
            listName: "Work",
            isCompleted: true,
            completionDate: date(2026, 8, 11, 15, 0),
            due: .timed(date(2026, 8, 11, 17, 0))
        )
        let sameDayDateOnly = ReminderRecord(
            listName: "Work",
            isCompleted: true,
            completionDate: date(2026, 8, 10, 22, 0),
            due: .dateOnly(year: 2026, month: 8, day: 10)
        )
        let oneDayLate = ReminderRecord(
            listName: "Work",
            isCompleted: true,
            completionDate: date(2026, 8, 12, 9, 0),
            due: .dateOnly(year: 2026, month: 8, day: 11)
        )
        let stats = engine().compute(
            reminders: [twoHoursEarly, sameDayDateOnly, oneDayLate],
            listNames: ["Work"]
        )
        let expected = (2 * 3600.0 + 0.0 + (-1 * 86_400.0)) / 3.0
        XCTAssertEqual(stats.overall.meanEarlySeconds, expected)
        XCTAssertEqual(stats.overall.formattedAverage, "7.3 hours late")
    }

    func testAverageFormatsAsDaysWhenAtLeast24Hours() {
        let twoDaysEarly = ReminderRecord(
            listName: "Work",
            isCompleted: true,
            completionDate: date(2026, 8, 9, 10, 0),
            due: .dateOnly(year: 2026, month: 8, day: 11)
        )
        let stats = engine().compute(reminders: [twoDaysEarly], listNames: ["Work"])
        XCTAssertEqual(stats.overall.formattedAverage, "2 days early")
    }

    func testPerListStatsAreIndependentAndOverallIsTheUnion() {
        let workOnTime = ReminderRecord(
            listName: "Work",
            isCompleted: true,
            completionDate: date(2026, 8, 11, 16, 0),
            due: .timed(date(2026, 8, 11, 17, 0))
        )
        let personalLate = ReminderRecord(
            listName: "Personal",
            isCompleted: true,
            completionDate: date(2026, 8, 11, 18, 0),
            due: .timed(date(2026, 8, 11, 17, 0))
        )
        let ignored = ReminderRecord(
            listName: "Shopping",
            isCompleted: true,
            completionDate: date(2026, 8, 11, 10, 0),
            due: .timed(date(2026, 8, 11, 12, 0))
        )
        let stats = engine().compute(
            reminders: [workOnTime, personalLate, ignored],
            listNames: ["Work", "Personal"]
        )
        XCTAssertEqual(stats.byList.map(\.listName), ["Work", "Personal"])
        XCTAssertEqual(stats.byList[0].onTimeCount, 1)
        XCTAssertEqual(stats.byList[0].lateCount, 0)
        XCTAssertEqual(stats.byList[1].onTimeCount, 0)
        XCTAssertEqual(stats.byList[1].lateCount, 1)
        XCTAssertEqual(stats.overall.onTimeCount, 1)
        XCTAssertEqual(stats.overall.lateCount, 1)
        XCTAssertEqual(stats.overall.datedCompletionCount, 2)
    }

    func testEmptyAllowListedListReportsZerosAndNAAverage() {
        let stats = engine().compute(reminders: [], listNames: ["Work"])
        XCTAssertEqual(stats.byList.count, 1)
        XCTAssertEqual(stats.byList[0].listName, "Work")
        XCTAssertEqual(stats.byList[0].onTimeCount, 0)
        XCTAssertEqual(stats.byList[0].openOverdueCount, 0)
        XCTAssertEqual(stats.byList[0].completedThisWeek, 0)
        XCTAssertEqual(stats.byList[0].formattedAverage, "n/a")
        XCTAssertEqual(stats.overall.formattedAverage, "n/a")
    }

    func testCompletedWithoutCompletionDateIsTreatedAsOpen() {
        let reminder = ReminderRecord(
            listName: "Work",
            isCompleted: true,
            completionDate: nil,
            due: .timed(date(2026, 8, 11, 17, 0))
        )
        let stats = engine().compute(reminders: [reminder], listNames: ["Work"])
        XCTAssertEqual(stats.overall.onTimeCount, 0)
        XCTAssertEqual(stats.overall.completedThisWeek, 0)
        XCTAssertEqual(stats.overall.openOverdueCount, 1)
    }
}
