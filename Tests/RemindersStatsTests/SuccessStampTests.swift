import Foundation
import XCTest
@testable import RemindersStats

final class SuccessStampTests: XCTestCase {
    func testSkipsWhenLastSuccessIsNewerThan12Hours() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stamp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let stamp = SuccessStamp(url: url, minimumInterval: 12 * 3600)
        let now = Date(timeIntervalSince1970: 1_000_000)
        try stamp.markSuccess(at: now.addingTimeInterval(-11 * 3600))
        XCTAssertTrue(stamp.shouldSkip(now: now, force: false))
    }

    func testRunsWhenLastSuccessIsOlderThan12Hours() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stamp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let stamp = SuccessStamp(url: url, minimumInterval: 12 * 3600)
        let now = Date(timeIntervalSince1970: 1_000_000)
        try stamp.markSuccess(at: now.addingTimeInterval(-12 * 3600 - 1))
        XCTAssertFalse(stamp.shouldSkip(now: now, force: false))
    }

    func testForceIgnoresFreshStamp() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stamp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let stamp = SuccessStamp(url: url, minimumInterval: 12 * 3600)
        let now = Date(timeIntervalSince1970: 1_000_000)
        try stamp.markSuccess(at: now)
        XCTAssertFalse(stamp.shouldSkip(now: now, force: true))
    }

    func testMissingStampDoesNotSkip() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-stamp-\(UUID().uuidString)")
        let stamp = SuccessStamp(url: url, minimumInterval: 12 * 3600)
        XCTAssertFalse(stamp.shouldSkip(now: Date(), force: false))
    }
}
