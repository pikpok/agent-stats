import Foundation

@main
enum AgentStatsBarMain {
    static func main() async {
        let command = CLICommand(arguments: CommandLine.arguments)

        switch command.mode {
        case .launchApp(let background):
            AppRuntime.configure(showsDashboardOnLaunch: !background)
            AgentStatsBarApp.main()
        case .dumpSnapshot:
            await SnapshotCLI.dumpSnapshot()
        case .installClaudeHelper:
            await SnapshotCLI.installClaudeHelper()
        case .enableLaunchAtLogin:
            LaunchAtLoginCLI.enable()
        case .disableLaunchAtLogin:
            LaunchAtLoginCLI.disable()
        case .launchAtLoginStatus:
            LaunchAtLoginCLI.printStatus()
        }
    }
}

struct CLICommand {
    enum Mode {
        case launchApp(background: Bool)
        case dumpSnapshot
        case installClaudeHelper
        case enableLaunchAtLogin
        case disableLaunchAtLogin
        case launchAtLoginStatus
    }

    let mode: Mode

    init(arguments: [String]) {
        if arguments.contains("--dump-snapshot") {
            mode = .dumpSnapshot
        } else if arguments.contains("--install-claude-helper") {
            mode = .installClaudeHelper
        } else if arguments.contains("--enable-launch-at-login") {
            mode = .enableLaunchAtLogin
        } else if arguments.contains("--disable-launch-at-login") {
            mode = .disableLaunchAtLogin
        } else if arguments.contains("--launch-at-login-status") {
            mode = .launchAtLoginStatus
        } else {
            mode = .launchApp(background: arguments.contains("--background"))
        }
    }
}
