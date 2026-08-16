import Foundation

public struct SuccessStamp: Sendable {
    public var url: URL
    public var minimumInterval: TimeInterval

    public init(url: URL, minimumInterval: TimeInterval = 12 * 3600) {
        self.url = url
        self.minimumInterval = minimumInterval
    }

    public func shouldSkip(now: Date, force: Bool) -> Bool {
        if force { return false }
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let interval = TimeInterval(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return false
        }
        let last = Date(timeIntervalSince1970: interval)
        return now.timeIntervalSince(last) < minimumInterval
    }

    public func markSuccess(at date: Date) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try String(date.timeIntervalSince1970).write(to: url, atomically: true, encoding: .utf8)
    }
}

public struct RunLock: Sendable {
    public var url: URL

    public init(url: URL) {
        self.url = url
    }

    public func acquire() throws -> Bool {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let created = FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
        if created { return true }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) > 30 * 60
        {
            try? FileManager.default.removeItem(at: url)
            return FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
        }
        return false
    }

    public func release() {
        try? FileManager.default.removeItem(at: url)
    }
}
