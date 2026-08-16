import Foundation

public struct AppConfig: Equatable, Sendable {
    public var notionToken: String
    public var notionPageId: String
    public var lists: [String]

    public init(notionToken: String, notionPageId: String, lists: [String]) {
        self.notionToken = notionToken
        self.notionPageId = notionPageId
        self.lists = lists
    }

    public enum Error: Swift.Error, Equatable {
        case missingField(String)
        case invalidSyntax(String)
        case unreadableFile(String)
    }

    public static func parse(_ text: String, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> AppConfig {
        var token: String?
        var pageId: String?
        var lists: [String] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else {
                throw Error.invalidSyntax(String(line))
            }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "notion_token":
                token = try unquote(value)
            case "notion_page_id":
                pageId = try unquote(value)
            case "lists":
                lists = try parseList(value)
            default:
                throw Error.invalidSyntax(String(key))
            }
        }

        if let envToken = environment["NOTION_TOKEN"], !envToken.isEmpty {
            token = envToken
        }

        guard let token, !token.isEmpty else { throw Error.missingField("notion_token") }
        guard let pageId, !pageId.isEmpty else { throw Error.missingField("notion_page_id") }
        return AppConfig(notionToken: token, notionPageId: pageId, lists: lists)
    }

    public static func load(
        from url: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> AppConfig {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw Error.unreadableFile(url.path)
        }
        return try parse(text, environment: environment)
    }

    private static func unquote(_ raw: String) throws -> String {
        guard raw.hasPrefix("\""), raw.hasSuffix("\""), raw.count >= 2 else {
            throw Error.invalidSyntax(raw)
        }
        return String(raw.dropFirst().dropLast())
    }

    private static func parseList(_ raw: String) throws -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else {
            throw Error.invalidSyntax(raw)
        }
        let inner = trimmed.dropFirst().dropLast()
        if inner.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        return try inner.split(separator: ",").map { part in
            try unquote(part.trimmingCharacters(in: .whitespaces))
        }
    }
}

public enum ListSelection {
    public enum Error: Swift.Error, Equatable {
        case emptyAllowList
        case unknownLists(unknown: [String], available: [String])
    }

    public static func validate(allowList: [String], available: [String]) throws {
        if allowList.isEmpty { throw Error.emptyAllowList }
        let availableSet = Set(available)
        let unknown = allowList.filter { !availableSet.contains($0) }
        if !unknown.isEmpty {
            throw Error.unknownLists(unknown: unknown, available: available)
        }
    }
}
