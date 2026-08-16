import Foundation
import XCTest
@testable import RemindersStats

final class DueFromComponentsTests: XCTestCase {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    func testNilHourAndMinuteIsDateOnly() {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 8
        parts.day = 15
        let due = ReminderRecord.Due.from(components: parts, calendar: calendar())
        XCTAssertEqual(due, .dateOnly(year: 2026, month: 8, day: 15))
    }

    func testMidnightStoredAsAllDayIsDateOnly() {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 8
        parts.day = 15
        parts.hour = 0
        parts.minute = 0
        let due = ReminderRecord.Due.from(components: parts, calendar: calendar())
        XCTAssertEqual(due, .dateOnly(year: 2026, month: 8, day: 15))
    }

    func testAfternoonTimeIsTimed() {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 8
        parts.day = 15
        parts.hour = 17
        parts.minute = 30
        parts.timeZone = TimeZone(identifier: "Europe/Paris")
        let due = ReminderRecord.Due.from(components: parts, calendar: calendar())
        guard case let .timed(date) = due else {
            return XCTFail("expected timed due")
        }
        let got = calendar().dateComponents([.hour, .minute], from: date)
        XCTAssertEqual(got.hour, 17)
        XCTAssertEqual(got.minute, 30)
    }

    func testMissingDayIsNil() {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 8
        XCTAssertNil(ReminderRecord.Due.from(components: parts, calendar: calendar()))
    }
}
