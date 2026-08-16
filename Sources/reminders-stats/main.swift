import Foundation
import RemindersStats

@main
struct RemindersStatsCommand {
    static func main() async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = AppPaths.default(home: home)
        let runner = AppRunner(
            paths: paths,
            environment: ProcessInfo.processInfo.environment,
            reminders: EventKitReminderStore(),
            makeNotion: { NotionClient(token: $0) },
            agent: LaunchAgentInstaller(paths: paths),
            currentBinary: URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        )
        let code = await runner.run(arguments: CommandLine.arguments)
        Foundation.exit(code)
    }
}
