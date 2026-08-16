import Foundation

public struct AppRunner: Sendable {
    public var paths: AppPaths
    public var environment: [String: String]
    public var reminders: any ReminderReading
    public var makeNotion: @Sendable (String) -> any NotionPublishing
    public var now: @Sendable () -> Date
    public var timeZone: TimeZone
    public var agent: any AgentInstalling
    public var currentBinary: URL
    public var writeStdout: @Sendable (String) -> Void
    public var writeStderr: @Sendable (String) -> Void

    public init(
        paths: AppPaths,
        environment: [String: String],
        reminders: any ReminderReading,
        makeNotion: @escaping @Sendable (String) -> any NotionPublishing,
        now: @escaping @Sendable () -> Date = { Date() },
        timeZone: TimeZone = .current,
        agent: any AgentInstalling,
        currentBinary: URL,
        writeStdout: @escaping @Sendable (String) -> Void = { print($0, terminator: "") },
        writeStderr: @escaping @Sendable (String) -> Void = { fputs($0, stderr) }
    ) {
        self.paths = paths
        self.environment = environment
        self.reminders = reminders
        self.makeNotion = makeNotion
        self.now = now
        self.timeZone = timeZone
        self.agent = agent
        self.currentBinary = currentBinary
        self.writeStdout = writeStdout
        self.writeStderr = writeStderr
    }

    public func run(arguments: [String]) async -> Int32 {
        do {
            let command = try CommandParser.parse(arguments)
            switch command {
            case .help:
                writeStdout(Self.helpText)
                return 0
            case .lists:
                try await reminders.requestAccess()
                let names = try await reminders.listNames()
                if names.isEmpty {
                    writeStdout("No Reminders lists found.\n")
                } else {
                    writeStdout(names.joined(separator: "\n") + "\n")
                }
                return 0
            case let .sync(force):
                return await sync(force: force)
            case .installAgent:
                try agent.install(binarySource: currentBinary)
                writeStdout("Installed LaunchAgent at \(paths.launchAgent.path)\n")
                return 0
            case .uninstallAgent:
                try agent.uninstall()
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
            try await reminders.requestAccess()
            let available = try await reminders.listNames()
            try ListSelection.validate(allowList: config.lists, available: available)
            let remindersInLists = try await reminders.fetchReminders(inListNames: config.lists)
            let engine = StatsEngine.production(now: timestamp, timeZone: timeZone)
            let stats = engine.compute(reminders: remindersInLists, listNames: config.lists)
            let inventory = engine.openInventory(reminders: remindersInLists, listNames: config.lists)
            let text = DashboardRenderer.text(stats: stats, updatedAt: timestamp, timeZone: timeZone)
            writeStdout(text)
            let blocks = DashboardRenderer.blocks(
                stats: stats,
                updatedAt: timestamp,
                timeZone: timeZone,
                inventory: inventory
            )
            try await makeNotion(config.notionToken).replacePageBody(pageId: config.notionPageId, blocks: blocks)
            try stamp.markSuccess(at: timestamp)
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
        case ListSelection.Error.emptyAllowList:
            return "Config lists is empty. Run `reminders-stats lists` and add names to \(paths.config.path)."
        case ListSelection.Error.unknownLists(let unknown, let available):
            return """
            Unknown Reminders list(s): \(unknown.joined(separator: ", ")).
            Available: \(available.joined(separator: ", "))
            """
        case CommandParser.Error.unknownCommand(let name):
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

extension StatsEngine {
    public static func production(now: Date = Date(), timeZone: TimeZone = .current) -> StatsEngine {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return StatsEngine(calendar: calendar, now: now)
    }
}
