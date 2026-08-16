import Foundation

public protocol ReminderReading: Sendable {
    func requestAccess() async throws
    func listNames() async throws -> [String]
    func fetchReminders(inListNames names: [String]) async throws -> [ReminderRecord]
}

public enum ReminderAccessError: Error, Equatable, LocalizedError {
    case denied

    public var errorDescription: String? {
        "Reminders access was denied. Grant access in System Settings → Privacy & Security → Reminders, then run again."
    }
}

public protocol NotionPublishing: Sendable {
    func replacePageBody(pageId: String, blocks: [NotionBlock]) async throws
}

public enum NotionError: Error, Equatable, LocalizedError {
    case unauthorized
    case pageNotFound
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Notion rejected the token (401). Check notion_token in the config or the NOTION_TOKEN environment variable."
        case .pageNotFound:
            return "Notion page not found or not shared with the integration. Open the page, share it with the integration, and set notion_page_id."
        case let .http(code, body):
            return "Notion request failed (\(code)): \(body)"
        }
    }
}

public protocol AgentInstalling: Sendable {
    func install(binarySource: URL) throws
    func uninstall() throws
}
