import XCTest
@testable import RemindersStats

final class ConfigTests: XCTestCase {
    func testParsesTomlAllowListAndToken() throws {
        let text = """
        # comment
        notion_token = "secret_abc"
        notion_page_id = "page-123"
        lists = ["Work", "Personal"]
        """
        let config = try AppConfig.parse(text, environment: [:])
        XCTAssertEqual(config.notionToken, "secret_abc")
        XCTAssertEqual(config.notionPageId, "page-123")
        XCTAssertEqual(config.lists, ["Work", "Personal"])
    }

    func testEnvironmentTokenOverridesFile() throws {
        let text = """
        notion_token = "from-file"
        notion_page_id = "page-123"
        lists = ["Work"]
        """
        let config = try AppConfig.parse(text, environment: ["NOTION_TOKEN": "from-env"])
        XCTAssertEqual(config.notionToken, "from-env")
    }

    func testMissingPageIdThrows() {
        let text = """
        notion_token = "secret_abc"
        lists = ["Work"]
        """
        XCTAssertThrowsError(try AppConfig.parse(text, environment: [:])) { error in
            XCTAssertEqual(error as? AppConfig.Error, .missingField("notion_page_id"))
        }
    }

    func testMissingTokenAfterEnvThrows() {
        let text = """
        notion_page_id = "page-123"
        lists = ["Work"]
        """
        XCTAssertThrowsError(try AppConfig.parse(text, environment: [:])) { error in
            XCTAssertEqual(error as? AppConfig.Error, .missingField("notion_token"))
        }
    }
}

final class ListSelectionTests: XCTestCase {
    func testEmptyAllowListIsInvalid() {
        XCTAssertThrowsError(try validateLists(allowList: [], available: ["Work"])) { error in
            XCTAssertEqual(error as? ListError, .emptyAllowList)
        }
    }

    func testUnknownNamesAreInvalid() {
        XCTAssertThrowsError(try validateLists(allowList: ["Work", "Nope"], available: ["Work", "Personal"])) { error in
            XCTAssertEqual(
                error as? ListError,
                .unknownLists(unknown: ["Nope"], available: ["Work", "Personal"])
            )
        }
    }

    func testExactNamesPass() throws {
        try validateLists(allowList: ["Work"], available: ["Work", "Personal"])
    }
}
