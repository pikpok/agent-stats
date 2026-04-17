import Foundation

struct LaunchAtLoginStatus: Sendable {
    let isEnabled: Bool
    let launchAgentURL: URL
    let targetDescription: String
    let isRunningFromAppBundle: Bool
    let needsRefresh: Bool
}

enum LaunchAtLoginError: LocalizedError {
    case executableNotFound

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "The current app location could not be resolved."
        }
    }
}

struct LaunchAtLoginManager {
    static let launchAgentLabel = "com.pikpok.AgentStatsBar"

    private let fileManager: FileManager
    private let homeDirectory: URL
    private let bundleURL: URL
    private let executableURL: URL?

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        bundleURL: URL = Bundle.main.bundleURL,
        executableURL: URL? = Bundle.main.executableURL
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        self.bundleURL = bundleURL.standardizedFileURL
        self.executableURL = executableURL?.standardizedFileURL
    }

    func status() -> LaunchAtLoginStatus {
        let launchAgentURL = launchAgentURL()
        guard let target = currentTarget() else {
            return LaunchAtLoginStatus(
                isEnabled: false,
                launchAgentURL: launchAgentURL,
                targetDescription: "Unavailable",
                isRunningFromAppBundle: false,
                needsRefresh: false
            )
        }

        let existingArguments = existingProgramArguments(at: launchAgentURL)
        let isEnabled = existingArguments == target.programArguments
        let needsRefresh = existingArguments != nil && !isEnabled

        return LaunchAtLoginStatus(
            isEnabled: isEnabled,
            launchAgentURL: launchAgentURL,
            targetDescription: target.description,
            isRunningFromAppBundle: target.isAppBundle,
            needsRefresh: needsRefresh
        )
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        let launchAgentURL = launchAgentURL()

        if enabled {
            guard let target = currentTarget() else {
                throw LaunchAtLoginError.executableNotFound
            }

            try fileManager.createDirectory(
                at: launchAgentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )

            let propertyList = makePropertyList(for: target)
            let data = try PropertyListSerialization.data(fromPropertyList: propertyList, format: .xml, options: 0)
            try data.write(to: launchAgentURL, options: .atomic)
        } else if fileManager.fileExists(atPath: launchAgentURL.path) {
            try fileManager.removeItem(at: launchAgentURL)
        }

        return status()
    }

    private func launchAgentURL() -> URL {
        homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent("\(Self.launchAgentLabel).plist")
    }

    private func currentTarget() -> LaunchTarget? {
        if bundleURL.pathExtension == "app" {
            return .appBundle(bundleURL)
        }

        if let executableURL {
            return .executable(executableURL)
        }

        guard let executablePath = CommandLine.arguments.first, !executablePath.isEmpty else {
            return nil
        }

        let resolvedURL: URL
        if executablePath.hasPrefix("/") {
            resolvedURL = URL(fileURLWithPath: executablePath)
        } else {
            resolvedURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent(executablePath)
        }

        return .executable(resolvedURL.standardizedFileURL)
    }

    private func makePropertyList(for target: LaunchTarget) -> [String: Any] {
        var propertyList: [String: Any] = [
            "Label": Self.launchAgentLabel,
            "ProgramArguments": target.programArguments,
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": ["Aqua"],
        ]

        if let workingDirectory = target.workingDirectory {
            propertyList["WorkingDirectory"] = workingDirectory
        }

        return propertyList
    }

    private func existingProgramArguments(at url: URL) -> [String]? {
        guard
            let data = try? Data(contentsOf: url),
            let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dictionary = propertyList as? [String: Any]
        else {
            return nil
        }

        return dictionary["ProgramArguments"] as? [String]
    }
}

enum LaunchTarget: Equatable, Sendable {
    case appBundle(URL)
    case executable(URL)

    var programArguments: [String] {
        switch self {
        case .appBundle(let url):
            return ["/usr/bin/open", "-g", "-j", url.path, "--args", "--background"]
        case .executable(let url):
            return [url.path, "--background"]
        }
    }

    var workingDirectory: String? {
        switch self {
        case .appBundle:
            return nil
        case .executable(let url):
            return url.deletingLastPathComponent().path
        }
    }

    var description: String {
        switch self {
        case .appBundle(let url):
            return url.path
        case .executable(let url):
            return url.path
        }
    }

    var isAppBundle: Bool {
        switch self {
        case .appBundle:
            return true
        case .executable:
            return false
        }
    }
}
