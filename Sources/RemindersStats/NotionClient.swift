import Foundation

public struct NotionClient: NotionPublishing {
    public var token: String
    public var session: URLSession
    public var apiVersion: String

    public init(token: String, session: URLSession = .shared, apiVersion: String = "2022-06-28") {
        self.token = token
        self.session = session
        self.apiVersion = apiVersion
    }

    public func replacePageBody(pageId: String, blocks: [NotionBlock]) async throws {
        var cursor: String?
        repeat {
            let (ids, next) = try await listChildren(pageId: pageId, cursor: cursor)
            for id in ids {
                try await deleteBlock(id: id)
            }
            cursor = next
        } while cursor != nil

        if !blocks.isEmpty {
            try await append(pageId: pageId, blocks: blocks)
            try await linkOverdueCard(pageId: pageId)
        }
    }

    private func listChildren(pageId: String, cursor: String?) async throws -> ([String], String?) {
        let json = try await listChildrenJSON(parentId: pageId, cursor: cursor)
        let results = json["results"] as? [[String: Any]] ?? []
        let ids = results.compactMap { $0["id"] as? String }
        let next = json["has_more"] as? Bool == true ? json["next_cursor"] as? String : nil
        return (ids, next)
    }

    private func listAllChildren(parentId: String) async throws -> [[String: Any]] {
        var all: [[String: Any]] = []
        var cursor: String?
        repeat {
            let json = try await listChildrenJSON(parentId: parentId, cursor: cursor)
            all.append(contentsOf: json["results"] as? [[String: Any]] ?? [])
            cursor = json["has_more"] as? Bool == true ? json["next_cursor"] as? String : nil
        } while cursor != nil
        return all
    }

    private func listChildrenJSON(parentId: String, cursor: String?) async throws -> [String: Any] {
        var components = URLComponents(string: "https://api.notion.com/v1/blocks/\(parentId)/children")!
        var items = [URLQueryItem(name: "page_size", value: "100")]
        if let cursor {
            items.append(URLQueryItem(name: "start_cursor", value: cursor))
        }
        components.queryItems = items
        return try await request(url: components.url!, method: "GET", body: nil)
    }

    private func linkOverdueCard(pageId: String) async throws {
        let top = try await listAllChildren(parentId: pageId)
        guard let headingId = NotionAnchor.headingID(titled: "Overdue", in: top) else { return }
        let url = NotionAnchor.blockURL(pageId: pageId, blockId: headingId)
        for block in top where block["type"] as? String == "column_list" {
            guard let listId = block["id"] as? String else { continue }
            let columns = try await listAllChildren(parentId: listId)
            for column in columns {
                guard let columnId = column["id"] as? String else { continue }
                let children = try await listAllChildren(parentId: columnId)
                for child in children where NotionAnchor.calloutContains("Open overdue", block: child) {
                    guard let calloutId = child["id"] as? String else { continue }
                    let rich = NotionAnchor.applyLink(to: NotionAnchor.calloutRichText(child), url: url)
                    try await updateCallout(id: calloutId, richText: rich)
                    return
                }
            }
        }
    }

    private func updateCallout(id: String, richText: [[String: Any]]) async throws {
        let payload = try JSONSerialization.data(withJSONObject: [
            "callout": ["rich_text": richText],
        ])
        _ = try await request(
            url: URL(string: "https://api.notion.com/v1/blocks/\(id)")!,
            method: "PATCH",
            body: payload
        )
    }

    private func deleteBlock(id: String) async throws {
        _ = try await request(url: URL(string: "https://api.notion.com/v1/blocks/\(id)")!, method: "DELETE", body: nil)
    }

    private func append(pageId: String, blocks: [NotionBlock]) async throws {
        let payload = try NotionJSON.childrenPayload(blocks)
        _ = try await request(
            url: URL(string: "https://api.notion.com/v1/blocks/\(pageId)/children")!,
            method: "PATCH",
            body: payload
        )
    }

    private func request(url: URL, method: String, body: Data?) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(apiVersion, forHTTPHeaderField: "Notion-Version")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw NotionError.unauthorized }
        if code == 404 { throw NotionError.pageNotFound }
        if !(200...299).contains(code) {
            throw NotionError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        if data.isEmpty { return [:] }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

enum NotionJSON {
    static func childrenPayload(_ blocks: [NotionBlock]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["children": blocks.map(encode)])
    }

    static func encode(_ block: NotionBlock) -> [String: Any] {
        switch block {
        case let .heading2(text):
            return typed("heading_2", text)
        case let .heading3(text):
            return typed("heading_3", text)
        case let .callout(text):
            return [
                "object": "block",
                "type": "callout",
                "callout": [
                    "rich_text": rich([RichTextSpan(text: text)]),
                    "icon": ["type": "emoji", "emoji": "📊"],
                ],
            ]
        case let .bulleted(text):
            return [
                "object": "block",
                "type": "bulleted_list_item",
                "bulleted_list_item": [
                    "rich_text": rich([RichTextSpan(text: text)]),
                ],
            ]
        case let .paragraph(spans):
            return [
                "object": "block",
                "type": "paragraph",
                "paragraph": ["rich_text": rich(spans)],
            ]
        case let .metricCallout(spans, emoji, color):
            return [
                "object": "block",
                "type": "callout",
                "callout": [
                    "rich_text": rich(spans),
                    "icon": ["type": "emoji", "emoji": emoji],
                    "color": color,
                ],
            ]
        case .divider:
            return [
                "object": "block",
                "type": "divider",
                "divider": [:],
            ]
        case let .columnList(columns):
            return [
                "object": "block",
                "type": "column_list",
                "column_list": [
                    "children": columns.map { columnBlocks -> [String: Any] in
                        [
                            "object": "block",
                            "type": "column",
                            "column": [
                                "children": columnBlocks.map(encode),
                            ],
                        ]
                    },
                ],
            ]
        case let .table(width, hasColumnHeader, hasRowHeader, rows):
            return [
                "object": "block",
                "type": "table",
                "table": [
                    "table_width": width,
                    "has_column_header": hasColumnHeader,
                    "has_row_header": hasRowHeader,
                    "children": rows.map { row -> [String: Any] in
                        [
                            "object": "block",
                            "type": "table_row",
                            "table_row": [
                                "cells": row.map { rich($0) },
                            ],
                        ]
                    },
                ],
            ]
        }
    }

    private static func typed(_ type: String, _ text: String) -> [String: Any] {
        [
            "object": "block",
            "type": type,
            type: ["rich_text": rich([RichTextSpan(text: text)])],
        ]
    }

    private static func rich(_ spans: [RichTextSpan]) -> [[String: Any]] {
        spans.map { span in
            var text: [String: Any] = ["content": String(span.text.prefix(2000))]
            if let link = span.link {
                text["link"] = ["url": link]
            }
            return [
                "type": "text",
                "text": text,
                "annotations": [
                    "bold": span.bold,
                    "italic": span.italic,
                    "strikethrough": false,
                    "underline": false,
                    "code": false,
                    "color": span.color,
                ],
            ]
        }
    }
}

enum NotionAnchor {
    static func compactID(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: value), let host = url.host, host.contains("notion") {
            value = url.path.split(separator: "/").last.map(String.init) ?? value
        }
        let hex = value.filter(\.isHexDigit)
        if hex.count >= 32 {
            return String(hex.suffix(32)).lowercased()
        }
        return value.replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func blockURL(pageId: String, blockId: String) -> String {
        "https://www.notion.so/\(compactID(pageId))#\(compactID(blockId))"
    }

    static func headingID(titled title: String, in blocks: [[String: Any]]) -> String? {
        for block in blocks where block["type"] as? String == "heading_2" {
            if plainText(block["heading_2"] as? [String: Any]) == title {
                return block["id"] as? String
            }
        }
        return nil
    }

    static func calloutContains(_ needle: String, block: [String: Any]) -> Bool {
        guard block["type"] as? String == "callout" else { return false }
        return plainText(block["callout"] as? [String: Any]).contains(needle)
    }

    static func applyLink(to richText: [[String: Any]], url: String) -> [[String: Any]] {
        richText.map { span in
            var copy = span
            var text = span["text"] as? [String: Any] ?? [:]
            text["link"] = ["url": url]
            copy["text"] = text
            return copy
        }
    }

    static func calloutRichText(_ block: [String: Any]) -> [[String: Any]] {
        let callout = block["callout"] as? [String: Any] ?? [:]
        return callout["rich_text"] as? [[String: Any]] ?? []
    }

    private static func plainText(_ container: [String: Any]?) -> String {
        let spans = container?["rich_text"] as? [[String: Any]] ?? []
        return spans.map { span in
            if let plain = span["plain_text"] as? String { return plain }
            let text = span["text"] as? [String: Any]
            return text?["content"] as? String ?? ""
        }.joined()
    }
}
