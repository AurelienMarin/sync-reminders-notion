import Foundation
import XCTest
@testable import RemindersStats

final class AppRunnerTests: XCTestCase {
    func testSyncSkipsWhenStampIsFresh() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = makePaths(in: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        try? FileManager.default.createDirectory(at: paths.stamp.deletingLastPathComponent(), withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 2_000_000)
        try? SuccessStamp(url: paths.stamp).markSuccess(at: now.addingTimeInterval(-60))

        let reminders = MockReminders(names: ["Work"], records: [])
        let notion = MockNotion()
        let output = OutputBox()
        let runner = makeRunner(paths: paths, reminders: reminders, notion: notion, now: now, stdout: output)
        let code = await runner.run(arguments: ["reminders-stats", "sync"])
        XCTAssertEqual(code, 0)
        XCTAssertEqual(reminders.accessCount, 0)
        XCTAssertEqual(notion.calls.count, 0)
        XCTAssertTrue(output.text.contains("Skipped"))
    }

    func testSyncPublishesAndStampsOnSuccess() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = makePaths(in: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: paths.config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        notion_token = "secret"
        notion_page_id = "page-1"
        lists = ["Work"]
        """.write(to: paths.config, atomically: true, encoding: .utf8)

        let reminder = ReminderRecord(
            listName: "Work",
            isCompleted: true,
            completionDate: Date(timeIntervalSince1970: 1_900_000),
            due: .timed(Date(timeIntervalSince1970: 1_950_000))
        )
        let reminders = MockReminders(names: ["Work"], records: [reminder])
        let notion = MockNotion()
        let now = Date(timeIntervalSince1970: 2_000_000)
        let runner = makeRunner(paths: paths, reminders: reminders, notion: notion, now: now)
        let code = await runner.run(arguments: ["reminders-stats", "sync", "--force"])
        XCTAssertEqual(code, 0)
        XCTAssertEqual(notion.calls.count, 1)
        XCTAssertEqual(notion.calls.first?.0, "page-1")
        XCTAssertTrue(SuccessStamp(url: paths.stamp).shouldSkip(now: now.addingTimeInterval(60), force: false))
    }

    func testUnknownListDoesNotPublish() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = makePaths(in: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: paths.config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        notion_token = "secret"
        notion_page_id = "page-1"
        lists = ["Missing"]
        """.write(to: paths.config, atomically: true, encoding: .utf8)

        let reminders = MockReminders(names: ["Work"], records: [])
        let notion = MockNotion()
        let runner = makeRunner(paths: paths, reminders: reminders, notion: notion, now: Date())
        let code = await runner.run(arguments: ["reminders-stats", "sync", "--force"])
        XCTAssertEqual(code, 1)
        XCTAssertEqual(notion.calls.count, 0)
    }

    private func makePaths(in dir: URL) -> AppPaths {
        AppPaths(
            config: dir.appendingPathComponent("config.toml"),
            stamp: dir.appendingPathComponent("last_success"),
            lock: dir.appendingPathComponent("lock"),
            log: dir.appendingPathComponent("log"),
            installBinary: dir.appendingPathComponent("bin/reminders-stats"),
            launchAgent: dir.appendingPathComponent("agent.plist")
        )
    }

    private func makeRunner(
        paths: AppPaths,
        reminders: MockReminders,
        notion: MockNotion,
        now: Date,
        stdout: OutputBox = OutputBox()
    ) -> AppRunner {
        AppRunner(
            paths: paths,
            environment: [:],
            reminders: reminders,
            makeNotion: { _ in notion },
            now: { now },
            timeZone: TimeZone(secondsFromGMT: 0)!,
            agent: NoopAgent(),
            currentBinary: URL(fileURLWithPath: "/tmp/reminders-stats"),
            writeStdout: { stdout.text += $0 },
            writeStderr: { _ in }
        )
    }
}

final class OutputBox: @unchecked Sendable {
    var text = ""
}

final class MockReminders: ReminderReading, @unchecked Sendable {
    var names: [String]
    var records: [ReminderRecord]
    var accessCount = 0

    init(names: [String], records: [ReminderRecord]) {
        self.names = names
        self.records = records
    }

    func requestAccess() async throws {
        accessCount += 1
    }

    func listNames() async throws -> [String] { names }

    func fetchReminders(inListNames names: [String]) async throws -> [ReminderRecord] {
        records.filter { names.contains($0.listName) }
    }
}

final class MockNotion: NotionPublishing, @unchecked Sendable {
    var calls: [(String, [NotionBlock])] = []

    func replacePageBody(pageId: String, blocks: [NotionBlock]) async throws {
        calls.append((pageId, blocks))
    }
}

struct NoopAgent: AgentInstalling {
    func install(binarySource: URL) throws {}
    func uninstall() throws {}
}

final class NotionJSONTests: XCTestCase {
    func testEncodesHeadingAndBullets() throws {
        let data = try NotionJSON.childrenPayload([
            .heading2("Overall"),
            .bulleted("On time 1"),
        ])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let children = try XCTUnwrap(json["children"] as? [[String: Any]])
        XCTAssertEqual(children[0]["type"] as? String, "heading_2")
        XCTAssertEqual(children[1]["type"] as? String, "bulleted_list_item")
    }

    func testEncodesColumnListCalloutAndTable() throws {
        let card = NotionBlock.metricCallout(
            spans: [RichTextSpan(text: "67%", bold: true)],
            emoji: "✅",
            color: "green_background"
        )
        let data = try NotionJSON.childrenPayload([
            .columnList([[card], [card]]),
            .table(
                width: 2,
                hasColumnHeader: true,
                hasRowHeader: true,
                rows: [
                    [[RichTextSpan(text: "List", bold: true)], [RichTextSpan(text: "On time", bold: true)]],
                    [[RichTextSpan(text: "Work")], [RichTextSpan(text: "2")]],
                ]
            ),
        ])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let children = try XCTUnwrap(json["children"] as? [[String: Any]])
        XCTAssertEqual(children[0]["type"] as? String, "column_list")
        let columnList = try XCTUnwrap(children[0]["column_list"] as? [String: Any])
        let columns = try XCTUnwrap(columnList["children"] as? [[String: Any]])
        XCTAssertEqual(columns.count, 2)
        XCTAssertEqual(columns[0]["type"] as? String, "column")
        let table = try XCTUnwrap(children[1]["table"] as? [String: Any])
        XCTAssertEqual(table["table_width"] as? Int, 2)
        let rows = try XCTUnwrap(table["children"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0]["type"] as? String, "table_row")
    }
}
