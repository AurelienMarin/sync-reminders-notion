import Foundation

struct LaunchAgentInstaller {
    var paths: AppPaths
    var uid: uid_t

    init(paths: AppPaths, uid: uid_t = getuid()) {
        self.paths = paths
        self.uid = uid
    }

    func install(binarySource: URL) throws {
        let fm = FileManager.default
        let destDir = paths.installBinary.deletingLastPathComponent()
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        if fm.fileExists(atPath: paths.installBinary.path) {
            try fm.removeItem(at: paths.installBinary)
        }
        try fm.copyItem(at: binarySource, to: paths.installBinary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.installBinary.path)
        _ = try run("/usr/bin/codesign", ["-s", "-", "--force", "--identifier", "dev.aumarin.reminders-stats", paths.installBinary.path])

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>dev.aumarin.reminders-stats</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(paths.installBinary.path)</string>
                <string>sync</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>StartInterval</key>
            <integer>900</integer>
            <key>StandardOutPath</key>
            <string>\(paths.log.path)</string>
            <key>StandardErrorPath</key>
            <string>\(paths.log.path)</string>
        </dict>
        </plist>
        """
        try fm.createDirectory(at: paths.launchAgent.deletingLastPathComponent(), withIntermediateDirectories: true)
        try plist.write(to: paths.launchAgent, atomically: true, encoding: .utf8)
        try fm.createDirectory(at: paths.log.deletingLastPathComponent(), withIntermediateDirectories: true)

        _ = try? run("/bin/launchctl", ["bootout", "gui/\(uid)", paths.launchAgent.path])
        _ = try run("/bin/launchctl", ["bootstrap", "gui/\(uid)", paths.launchAgent.path])
    }

    func uninstall() throws {
        _ = try? run("/bin/launchctl", ["bootout", "gui/\(uid)", paths.launchAgent.path])
        try? FileManager.default.removeItem(at: paths.launchAgent)
    }

    @discardableResult
    private func run(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw AgentError.commandFailed(launchPath, output)
        }
        return output
    }
}

enum AgentError: Error, LocalizedError {
    case commandFailed(String, String)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(command, output):
            return "\(command) failed: \(output)"
        }
    }
}
