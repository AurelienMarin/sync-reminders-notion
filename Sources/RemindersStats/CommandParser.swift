public enum Command: Equatable, Sendable {
    case lists
    case sync(force: Bool)
    case installAgent
    case uninstallAgent
    case help
}

public enum CommandParser {
    public enum Error: Swift.Error, Equatable {
        case unknownCommand(String)
    }

    public static func parse(_ args: [String]) throws -> Command {
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
            throw Error.unknownCommand(commandArgs[0])
        }
    }
}
