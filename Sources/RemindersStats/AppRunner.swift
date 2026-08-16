import Foundation

enum Command: Equatable {
    case lists
    case sync(force: Bool)
    case installAgent
    case uninstallAgent
    case help
}

enum CommandError: Error, Equatable {
    case unknownCommand(String)
}

func parseCommand(_ args: [String]) throws -> Command {
    let commandArgs = Array(args.dropFirst())
    if commandArgs.isEmpty { return .help }
    switch commandArgs[0] {
    case "lists":
        return .lists
    case "sync":
        return .sync(force: commandArgs.contains("--force"))
    case "install-agent":
        return .installAgent
    case "uninstall-agent":
        return .uninstallAgent
    case "help", "--help", "-h":
        return .help
    default:
        throw CommandError.unknownCommand(commandArgs[0])
    }
}

enum ListError: Error, Equatable {
    case emptyAllowList
    case unknownLists(unknown: [String], available: [String])
}

func validateLists(allowList: [String], available: [String]) throws {
    if allowList.isEmpty { throw ListError.emptyAllowList }
    let unknown = allowList.filter { !Set(available).contains($0) }
    if !unknown.isEmpty {
        throw ListError.unknownLists(unknown: unknown, available: available)
    }
}

public struct AppRunner: Sendable {
    var paths: AppPaths
    var environment: [String: String]
    var now: @Sendable () -> Date
    var timeZone: TimeZone
    var currentBinary: URL
    var writeStdout: @Sendable (String) -> Void
    var writeStderr: @Sendable (String) -> Void

    public init(
        paths: AppPaths,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: @escaping @Sendable () -> Date = { Date() },
        timeZone: TimeZone = .current,
        currentBinary: URL,
        writeStdout: @escaping @Sendable (String) -> Void = { print($0, terminator: "") },
        writeStderr: @escaping @Sendable (String) -> Void = { fputs($0, stderr) }
    ) {
        self.paths = paths
        self.environment = environment
        self.now = now
        self.timeZone = timeZone
        self.currentBinary = currentBinary
        self.writeStdout = writeStdout
        self.writeStderr = writeStderr
    }

    public func run(arguments: [String]) async -> Int32 {
        do {
            switch try parseCommand(arguments) {
            case .help:
                writeStdout(Self.helpText)
                return 0
            case .lists:
                let store = EventKitReminderStore()
                try await store.requestAccess()
                let names = try await store.listNames()
                writeStdout(names.isEmpty ? "No Reminders lists found.\n" : names.joined(separator: "\n") + "\n")
                return 0
            case let .sync(force):
                return await sync(force: force)
            case .installAgent:
                try LaunchAgentInstaller(paths: paths).install(binarySource: currentBinary)
                writeStdout("Installed LaunchAgent at \(paths.launchAgent.path)\n")
                return 0
            case .uninstallAgent:
                try LaunchAgentInstaller(paths: paths).uninstall()
                writeStdout("Removed LaunchAgent.\n")
                return 0
            }
        } catch {
            writeStderr(message(for: error) + "\n")
            return 1
        }
    }

    private func sync(force: Bool) async -> Int32 {
        let lock = RunLock(url: paths.lock)
        do {
            if try !lock.acquire() {
                writeStdout("Skipped: another reminders-stats run is in progress.\n")
                log("skipped: lock held")
                return 0
            }
        } catch {
            writeStderr(message(for: error) + "\n")
            return 1
        }
        defer { lock.release() }

        let stamp = SuccessStamp(url: paths.stamp)
        let timestamp = now()
        if stamp.shouldSkip(now: timestamp, force: force) {
            writeStdout("Skipped: last successful publish is newer than 12 hours (use sync --force).\n")
            log("skipped: last successful publish is newer than 12 hours (use sync --force)")
            return 0
        }

        do {
            let config = try AppConfig.load(from: paths.config, environment: environment)
            let store = EventKitReminderStore()
            try await store.requestAccess()
            let available = try await store.listNames()
            try validateLists(allowList: config.lists, available: available)
            let remindersInLists = try await store.fetchReminders(inListNames: config.lists)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            calendar.firstWeekday = 2
            calendar.minimumDaysInFirstWeek = 4
            let engine = StatsEngine(calendar: calendar, now: timestamp)
            let stats = engine.compute(reminders: remindersInLists, listNames: config.lists)
            let inventory = engine.openInventory(reminders: remindersInLists, listNames: config.lists)
            let blocks = DashboardRenderer.blocks(
                stats: stats,
                updatedAt: timestamp,
                timeZone: timeZone,
                inventory: inventory
            )
            try await NotionClient(token: config.notionToken).replacePageBody(pageId: config.notionPageId, blocks: blocks)
            try stamp.markSuccess(at: timestamp)
            writeStdout("Published Notion page \(config.notionPageId)\n")
            log("published Notion page \(config.notionPageId)")
            return 0
        } catch {
            writeStderr(message(for: error) + "\n")
            return 1
        }
    }

    private func log(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: now())
        let entry = "\(stamp) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: paths.log) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(entry.utf8))
        } else {
            try? FileManager.default.createDirectory(at: paths.log.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? entry.write(to: paths.log, atomically: true, encoding: .utf8)
        }
    }

    private func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        switch error {
        case AppConfig.Error.unreadableFile(let path):
            return "Could not read config at \(path). Copy config.example.toml to \(paths.config.path) and fill it in."
        case AppConfig.Error.missingField(let field):
            return "Config is missing \(field)."
        case ListError.emptyAllowList:
            return "Config lists is empty. Run `reminders-stats lists` and add names to \(paths.config.path)."
        case ListError.unknownLists(let unknown, let available):
            return """
            Unknown Reminders list(s): \(unknown.joined(separator: ", ")).
            Available: \(available.joined(separator: ", "))
            """
        case CommandError.unknownCommand(let name):
            return "Unknown command \(name).\n\(Self.helpText)"
        default:
            return String(describing: error)
        }
    }

    public static let helpText = """
    reminders-stats — Apple Reminders punctuality stats for Notion

    Commands:
      lists              Print Reminders list names
      sync [--force]     Compute stats and publish the Notion page
      install-agent      Install a LaunchAgent (login + every 15 minutes)
      uninstall-agent    Remove the LaunchAgent
      help               Show this help

    The tool skips sync when the last successful Notion write was less than 12 hours ago.

    """
}
