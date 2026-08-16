import Foundation

public struct AppPaths: Equatable, Sendable {
    public var config: URL
    public var stamp: URL
    public var lock: URL
    public var log: URL
    public var installBinary: URL
    public var launchAgent: URL

    public init(config: URL, stamp: URL, lock: URL, log: URL, installBinary: URL, launchAgent: URL) {
        self.config = config
        self.stamp = stamp
        self.lock = lock
        self.log = log
        self.installBinary = installBinary
        self.launchAgent = launchAgent
    }

    public static func `default`(home: URL) -> AppPaths {
        AppPaths(
            config: home.appendingPathComponent(".config/reminders-stats/config.toml"),
            stamp: home.appendingPathComponent(".local/state/reminders-stats/last_success"),
            lock: home.appendingPathComponent(".local/state/reminders-stats/lock"),
            log: home.appendingPathComponent("Library/Logs/reminders-stats.log"),
            installBinary: home.appendingPathComponent("Library/Application Support/reminders-stats/reminders-stats"),
            launchAgent: home.appendingPathComponent("Library/LaunchAgents/dev.aumarin.reminders-stats.plist")
        )
    }
}
