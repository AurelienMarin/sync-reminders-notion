import Foundation
import XCTest
@testable import RemindersStats

final class DashboardRendererTests: XCTestCase {
    func testRendersOverallAndPerListSections() {
        let overall = ListStats(
            listName: "Overall",
            onTimeCount: 2,
            lateCount: 1,
            datedCompletionCount: 3,
            onTimePercent: 66.666,
            latePercent: 33.333,
            openOverdueCount: 4,
            completedThisWeek: 5,
            completedThisMonth: 6,
            meanEarlySeconds: 5 * 3600
        )
        let work = ListStats(
            listName: "Work",
            onTimeCount: 2,
            lateCount: 0,
            datedCompletionCount: 2,
            onTimePercent: 100,
            latePercent: 0,
            openOverdueCount: 1,
            completedThisWeek: 2,
            completedThisMonth: 3,
            meanEarlySeconds: nil
        )
        let stats = DashboardStats(overall: overall, byList: [work])
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 8
        parts.day = 15
        parts.hour = 23
        parts.minute = 40
        parts.timeZone = TimeZone(identifier: "Europe/Paris")
        let updated = Calendar(identifier: .gregorian).date(from: parts)!

        let text = DashboardRenderer.text(
            stats: stats,
            updatedAt: updated,
            timeZone: TimeZone(identifier: "Europe/Paris")!
        )

        XCTAssertTrue(text.contains("Last updated: 15 Aug 2026, 23:40 (Europe/Paris)"), text)
        XCTAssertTrue(text.contains("Overall"), text)
        XCTAssertTrue(text.contains("On time"), text)
        XCTAssertTrue(text.contains("2  (67% of dated completions)"), text)
        XCTAssertTrue(text.contains("Late"), text)
        XCTAssertTrue(text.contains("1  (33%)"), text)
        XCTAssertTrue(text.contains("Open overdue"), text)
        XCTAssertTrue(text.contains("4"), text)
        XCTAssertTrue(text.contains("Done this week"), text)
        XCTAssertTrue(text.contains("5"), text)
        XCTAssertTrue(text.contains("Done this month"), text)
        XCTAssertTrue(text.contains("6"), text)
        XCTAssertTrue(text.contains("5 hours early"), text)
        XCTAssertTrue(text.contains("Work"), text)
        XCTAssertTrue(text.contains("n/a"), text)
    }

    func testNotionBlocksUseKpiColumnsAverageAndListTable() {
        let stats = sampleStats()
        let blocks = DashboardRenderer.blocks(
            stats: stats,
            updatedAt: sampleUpdatedAt(),
            timeZone: TimeZone(identifier: "Europe/Paris")!
        )

        guard case let .paragraph(spans) = blocks[0] else {
            return XCTFail("expected updated-at paragraph, got \(blocks[0])")
        }
        XCTAssertTrue(spans.map(\.text).joined().contains("15 Aug 2026, 23:40"))

        guard case let .heading2(title) = blocks[1] else {
            return XCTFail("expected Overall heading")
        }
        XCTAssertEqual(title, "Overall")

        guard case let .columnList(kpis) = blocks[2] else {
            return XCTFail("expected KPI column list, got \(blocks[2])")
        }
        XCTAssertEqual(kpis.count, 4)
        assertCallout(kpis[0], contains: "67%", color: "green_background")
        assertCallout(kpis[1], contains: "33%", color: "orange_background")
        assertCallout(kpis[2], contains: "4", color: "red_background")
        assertCallout(kpis[3], contains: "5", color: "blue_background")

        guard case let .columnList(secondary) = blocks[3] else {
            return XCTFail("expected average/month columns, got \(blocks[3])")
        }
        XCTAssertEqual(secondary.count, 2)
        assertCallout(secondary[0], contains: "5 hours early", color: "purple_background")
        assertCallout(secondary[1], contains: "6", color: "gray_background")

        XCTAssertEqual(blocks[4], .divider)
        guard case let .heading2(byList) = blocks[5] else {
            return XCTFail("expected By list heading")
        }
        XCTAssertEqual(byList, "By list")

        guard case let .table(width, hasHeader, _, rows) = blocks[6] else {
            return XCTFail("expected per-list table, got \(blocks[6])")
        }
        XCTAssertEqual(width, 7)
        XCTAssertTrue(hasHeader)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].map(\.plainText), ["List", "On time", "Late", "Overdue", "Week", "Month", "Avg"])
        XCTAssertEqual(rows[1][0].plainText, "Work")
        XCTAssertTrue(rows[1][1].plainText.contains("2"))
        XCTAssertTrue(rows[1][6].plainText.contains("n/a"))
    }

    func testOverdueCardIsGrayWhenNoneAreOpen() {
        var overall = sampleStats().overall
        overall.openOverdueCount = 0
        let stats = DashboardStats(overall: overall, byList: [])
        let blocks = DashboardRenderer.blocks(
            stats: stats,
            updatedAt: sampleUpdatedAt(),
            timeZone: TimeZone(identifier: "Europe/Paris")!
        )
        guard case let .columnList(kpis) = blocks[2] else {
            return XCTFail("expected KPI columns")
        }
        assertCallout(kpis[2], contains: "0", color: "gray_background")
    }

    func testListsOverdueAndOpenRemindersAsReadOnlyTables() {
        let inventory = OpenInventory(
            overdue: [
                OpenReminder(title: "File taxes", listName: "Work", due: .dateOnly(year: 2026, month: 8, day: 11)),
            ],
            open: [
                OpenReminder(title: "Standup notes", listName: "Work", due: .timed(
                    Calendar(identifier: .gregorian).date(from: DateComponents(
                        timeZone: TimeZone(identifier: "Europe/Paris"),
                        year: 2026, month: 8, day: 12, hour: 17, minute: 0
                    ))!
                )),
                OpenReminder(title: "Someday", listName: "Personal", due: nil),
            ]
        )
        let blocks = DashboardRenderer.blocks(
            stats: sampleStats(),
            updatedAt: sampleUpdatedAt(),
            timeZone: TimeZone(identifier: "Europe/Paris")!,
            inventory: inventory
        )

        let overdueHeading = blocks.first { if case .heading2("Overdue") = $0 { return true }; return false }
        XCTAssertNotNil(overdueHeading)

        guard let overdueTable = firstTable(after: "Overdue", in: blocks) else {
            return XCTFail("expected overdue table")
        }
        XCTAssertEqual(overdueTable[0].map(\.plainText), ["Reminder", "List", "Due", "Status"])
        XCTAssertEqual(overdueTable[1][0].plainText, "File taxes")
        XCTAssertEqual(overdueTable[1][3].plainText, "Overdue")

        guard let openTable = firstTable(after: "Open", in: blocks) else {
            return XCTFail("expected open table")
        }
        XCTAssertEqual(openTable[1][0].plainText, "Standup notes")
        XCTAssertEqual(openTable[1][3].plainText, "Open")
        XCTAssertEqual(openTable[2][2].plainText, "No due date")

        let note = blocks.compactMap { block -> String? in
            if case let .paragraph(spans) = block { return spans.map(\.text).joined() }
            return nil
        }.joined()
        XCTAssertTrue(note.contains("Apple Reminders"))
    }

    func testEmptyOpenSectionsShowNone() {
        let blocks = DashboardRenderer.blocks(
            stats: sampleStats(),
            updatedAt: sampleUpdatedAt(),
            timeZone: TimeZone(identifier: "Europe/Paris")!,
            inventory: OpenInventory(overdue: [], open: [])
        )
        let texts = blocks.compactMap { block -> String? in
            if case let .paragraph(spans) = block { return spans.map(\.text).joined() }
            return nil
        }
        XCTAssertGreaterThanOrEqual(texts.filter { $0 == "None" }.count, 2)
    }

    private func firstTable(after heading: String, in blocks: [NotionBlock]) -> [[[RichTextSpan]]]? {
        var seenHeading = false
        for block in blocks {
            if case let .heading2(title) = block, title == heading {
                seenHeading = true
                continue
            }
            if seenHeading, case let .table(_, _, _, rows) = block {
                return rows
            }
        }
        return nil
    }

    private func sampleStats() -> DashboardStats {
        let overall = ListStats(
            listName: "Overall",
            onTimeCount: 2,
            lateCount: 1,
            datedCompletionCount: 3,
            onTimePercent: 66.666,
            latePercent: 33.333,
            openOverdueCount: 4,
            completedThisWeek: 5,
            completedThisMonth: 6,
            meanEarlySeconds: 5 * 3600
        )
        let work = ListStats(
            listName: "Work",
            onTimeCount: 2,
            lateCount: 0,
            datedCompletionCount: 2,
            onTimePercent: 100,
            latePercent: 0,
            openOverdueCount: 1,
            completedThisWeek: 2,
            completedThisMonth: 3,
            meanEarlySeconds: nil
        )
        return DashboardStats(overall: overall, byList: [work])
    }

    private func sampleUpdatedAt() -> Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 8
        parts.day = 15
        parts.hour = 23
        parts.minute = 40
        parts.timeZone = TimeZone(identifier: "Europe/Paris")
        return Calendar(identifier: .gregorian).date(from: parts)!
    }

    private func assertCallout(_ column: [NotionBlock], contains needle: String, color: String, file: StaticString = #filePath, line: UInt = #line) {
        guard column.count == 1, case let .metricCallout(spans, _, calloutColor) = column[0] else {
            return XCTFail("expected a single styled callout, got \(column)", file: file, line: line)
        }
        XCTAssertEqual(calloutColor, color, file: file, line: line)
        XCTAssertTrue(spans.map(\.text).joined().contains(needle), spans.map(\.text).joined(), file: file, line: line)
    }
}

private extension [RichTextSpan] {
    var plainText: String { map(\.text).joined() }
}

final class CommandParserTests: XCTestCase {
    func testParsesSyncForceAndLists() throws {
        XCTAssertEqual(try CommandParser.parse(["reminders-stats", "lists"]), .lists)
        XCTAssertEqual(try CommandParser.parse(["reminders-stats", "sync"]), .sync(force: false))
        XCTAssertEqual(try CommandParser.parse(["reminders-stats", "sync", "--force"]), .sync(force: true))
        XCTAssertEqual(try CommandParser.parse(["reminders-stats", "install-agent"]), .installAgent)
        XCTAssertEqual(try CommandParser.parse(["reminders-stats", "uninstall-agent"]), .uninstallAgent)
    }

    func testUnknownCommandThrows() {
        XCTAssertThrowsError(try CommandParser.parse(["reminders-stats", "wat"])) { error in
            XCTAssertEqual(error as? CommandParser.Error, .unknownCommand("wat"))
        }
    }
}
