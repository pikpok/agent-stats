import Darwin
import Foundation

enum LaunchAtLoginCLI {
    static func enable() {
        let manager = LaunchAtLoginManager()

        do {
            let status = try manager.setEnabled(true)
            print("Launch at login enabled for \(status.targetDescription)")
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            Darwin.exit(EXIT_FAILURE)
        }
    }

    static func disable() {
        let manager = LaunchAtLoginManager()

        do {
            _ = try manager.setEnabled(false)
            print("Launch at login disabled.")
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            Darwin.exit(EXIT_FAILURE)
        }
    }

    static func printStatus() {
        let status = LaunchAtLoginManager().status()
        let state = status.isEnabled ? "enabled" : "disabled"
        print("Launch at login is \(state).")
        print("Target: \(status.targetDescription)")
        print("LaunchAgent: \(status.launchAgentURL.path)")
        if status.needsRefresh {
            print("Current LaunchAgent points to an older app location.")
        }
    }
}
