import Foundation
import XCTest
@testable import RemindersStats

final class NotionJSONTests: XCTestCase {
    func testEncodesHeadingAndParagraph() throws {
        let data = try NotionJSON.childrenPayload([
            .heading2("Overall"),
            .paragraph([RichTextSpan(text: "On time 1")]),
        ])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let children = try XCTUnwrap(json["children"] as? [[String: Any]])
        XCTAssertEqual(children[0]["type"] as? String, "heading_2")
        XCTAssertEqual(children[1]["type"] as? String, "paragraph")
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
