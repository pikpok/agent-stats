import Darwin
import Foundation

enum AppRuntime {
    private static let backgroundLaunchEnvironmentKey = "AGENT_STATS_BACKGROUND_LAUNCH"

    static var showsDashboardOnLaunch: Bool {
        ProcessInfo.processInfo.environment[backgroundLaunchEnvironmentKey] != "1"
    }

    static func configure(showsDashboardOnLaunch: Bool) {
        if showsDashboardOnLaunch {
            unsetenv(backgroundLaunchEnvironmentKey)
        } else {
            setenv(backgroundLaunchEnvironmentKey, "1", 1)
        }
    }
}
