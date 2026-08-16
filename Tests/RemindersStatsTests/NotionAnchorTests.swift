import XCTest
@testable import RemindersStats

final class NotionAnchorTests: XCTestCase {
    func testCompactsDashedAndSlugPageIds() {
        XCTAssertEqual(
            NotionAnchor.compactID("59833787-2cf9-4fdf-8782-e53db20768a5"),
            "598337872cf94fdf8782e53db20768a5"
        )
        XCTAssertEqual(
            NotionAnchor.compactID("https://www.notion.so/My-dashboard-598337872cf94fdf8782e53db20768a5"),
            "598337872cf94fdf8782e53db20768a5"
        )
    }

    func testBlockURLJoinsPageAndHeading() {
        let url = NotionAnchor.blockURL(
            pageId: "59833787-2cf9-4fdf-8782-e53db20768a5",
            blockId: "7af38973-3787-41b3-bd75-0ed3a1edfac9"
        )
        XCTAssertEqual(
            url,
            "https://www.notion.so/598337872cf94fdf8782e53db20768a5#7af38973378741b3bd750ed3a1edfac9"
        )
    }

    func testApplyLinkAddsURLToEachTextSpan() {
        let original: [[String: Any]] = [
            [
                "type": "text",
                "text": ["content": "4\n"],
                "annotations": ["bold": true],
            ],
            [
                "type": "text",
                "text": ["content": "Open overdue"],
                "annotations": ["color": "gray"],
            ],
        ]
        let linked = NotionAnchor.applyLink(to: original, url: "https://www.notion.so/page#heading")
        let first = linked[0]["text"] as? [String: Any]
        let second = linked[1]["text"] as? [String: Any]
        XCTAssertEqual(first?["link"] as? [String: String], ["url": "https://www.notion.so/page#heading"])
        XCTAssertEqual(second?["link"] as? [String: String], ["url": "https://www.notion.so/page#heading"])
        XCTAssertEqual(first?["content"] as? String, "4\n")
    }

    func testFindsHeadingIdAndOverdueCallout() {
        let top: [[String: Any]] = [
            [
                "id": "heading-overdue",
                "type": "heading_2",
                "heading_2": [
                    "rich_text": [["plain_text": "Overdue", "text": ["content": "Overdue"]]],
                ],
            ],
            ["id": "columns", "type": "column_list"],
        ]
        XCTAssertEqual(NotionAnchor.headingID(titled: "Overdue", in: top), "heading-overdue")

        let callout: [String: Any] = [
            "id": "overdue-card",
            "type": "callout",
            "callout": [
                "rich_text": [["plain_text": "4\nOpen overdue", "text": ["content": "Open overdue"]]],
            ],
        ]
        XCTAssertTrue(NotionAnchor.calloutContains("Open overdue", block: callout))
        XCTAssertFalse(NotionAnchor.calloutContains("Open overdue", block: top[0]))
    }

    func testEncodesRichTextLink() throws {
        let data = try NotionJSON.childrenPayload([
            .paragraph([RichTextSpan(text: "Open overdue", link: "https://www.notion.so/p#h")]),
        ])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let children = try XCTUnwrap(json["children"] as? [[String: Any]])
        let paragraph = try XCTUnwrap(children[0]["paragraph"] as? [String: Any])
        let rich = try XCTUnwrap(paragraph["rich_text"] as? [[String: Any]])
        let text = try XCTUnwrap(rich[0]["text"] as? [String: Any])
        XCTAssertEqual(text["link"] as? [String: String], ["url": "https://www.notion.so/p#h"])
    }
}
