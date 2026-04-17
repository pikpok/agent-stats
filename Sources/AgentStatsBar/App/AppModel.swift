import Foundation
import SwiftUI

enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case fiveHourOnly
    case fiveHourAndWeekly

    var id: String { rawValue }

    var pickerLabel: String {
        switch self {
        case .fiveHourOnly:
            return "5h"
        case .fiveHourAndWeekly:
            return "5h + 7d"
        }
    }
}

struct MenuBarServiceItem: Identifiable, Sendable {
    let service: ServiceKind
    let valueText: String

    var id: ServiceKind { service }
}

@MainActor
final class AppModel: ObservableObject {
    private static let menuBarDisplayModeDefaultsKey = "menuBarDisplayMode"

    @Published private(set) var snapshot = AppSnapshot.empty
    @Published private(set) var isRefreshing = false
    @Published private(set) var helperStatus = ClaudeHelperInstallStatus.notInstalled
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginNeedsRefresh = false
    @Published private(set) var launchAtLoginTargetDescription = "Unavailable"
    @Published private(set) var isRunningFromAppBundle = false
    @Published var transientMessage: String?
    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            userDefaults.set(menuBarDisplayMode.rawValue, forKey: Self.menuBarDisplayModeDefaultsKey)
        }
    }

    private let helperInstaller = ClaudeStatuslineHelperInstaller()
    private let codexProvider = CodexUsageProvider()
    private let cursorProvider = CursorUsageProvider()
    private let userDefaults: UserDefaults
    private let launchAtLoginManager: LaunchAtLoginManager
    private lazy var claudeProvider = ClaudeUsageProvider(helperInstaller: helperInstaller)
    private var pollingTask: Task<Void, Never>?

    init(
        userDefaults: UserDefaults = .standard,
        launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager()
    ) {
        self.userDefaults = userDefaults
        self.launchAtLoginManager = launchAtLoginManager
        self.menuBarDisplayMode = Self.loadMenuBarDisplayMode(from: userDefaults)
        refreshLaunchAtLoginStatus()
        startPolling()
    }

    deinit {
        pollingTask?.cancel()
    }

    var menuBarTitle: String {
        let segments = menuBarItems.map { "\($0.service.compactLabel) \($0.valueText)" }
        return segments.isEmpty ? "Agent Stats" : segments.joined(separator: "  ")
    }

    var menuBarItems: [MenuBarServiceItem] {
        snapshot.services.compactMap { service in
            guard let valueText = Self.compactValue(for: service, mode: menuBarDisplayMode) else {
                return nil
            }

            return MenuBarServiceItem(service: service.service, valueText: valueText)
        }
    }

    var menuBarSymbol: String {
        snapshot.services.contains(where: { $0.state == .needsSetup || $0.state == .stale || $0.state == .error })
            ? "exclamationmark.circle"
            : "gauge.with.dots.needle.50percent"
    }

    var shouldShowMenuBarSymbol: Bool {
        snapshot.services.contains(where: { $0.state == .needsSetup || $0.state == .stale || $0.state == .error })
    }

    var launchAtLoginCaption: String {
        if launchAtLoginNeedsRefresh {
            return "Startup is configured for an older path. Re-enable it from the current app build."
        }

        if isRunningFromAppBundle {
            return "Starts this app in the background the next time you log in."
        }

        return "Startup follows the current executable path. Use the bundled .app for a stable install."
    }

    func refreshNow() {
        Task {
            await refresh()
        }
    }

    func installClaudeHelper() {
        Task {
            let result = helperInstaller.install()
            transientMessage = result.userMessage
            await refresh()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            let status = try launchAtLoginManager.setEnabled(enabled)
            applyLaunchAtLoginStatus(status)
            transientMessage = enabled
                ? "Launch at login enabled. Agent Stats will start in the background next time you log in."
                : "Launch at login disabled."
        } catch {
            refreshLaunchAtLoginStatus()
            transientMessage = error.localizedDescription
        }
    }

    func refreshLaunchAtLoginStatus() {
        applyLaunchAtLoginStatus(launchAtLoginManager.status())
    }

    private func startPolling() {
        pollingTask = Task {
            await refresh()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await refresh()
            }
        }
    }

    private func refresh() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        transientMessage = nil

        let helperStatus = helperInstaller.status()
        self.helperStatus = helperStatus

        async let codexSnapshot = codexProvider.fetch()
        async let claudeSnapshot = claudeProvider.fetch()
        async let cursorSnapshot = cursorProvider.fetch()

        let services = await [codexSnapshot, claudeSnapshot, cursorSnapshot]
            .sorted { $0.service.sortOrder < $1.service.sortOrder }

        snapshot = AppSnapshot(fetchedAt: Date(), services: services)
        isRefreshing = false
    }

    private func applyLaunchAtLoginStatus(_ status: LaunchAtLoginStatus) {
        launchAtLoginEnabled = status.isEnabled
        launchAtLoginNeedsRefresh = status.needsRefresh
        launchAtLoginTargetDescription = status.targetDescription
        isRunningFromAppBundle = status.isRunningFromAppBundle
    }

    nonisolated static func compactValue(for service: ServiceSnapshot, mode: MenuBarDisplayMode) -> String? {
        let primaryWindow: UsageWindow?
        let secondaryWindow: UsageWindow?

        switch service.service {
        case .cursor:
            primaryWindow =
                service.windows.first(where: { $0.title == "Plan" })
                ?? service.windows.first(where: { $0.title == "Included" })
                ?? service.windows.first(where: { $0.title == "5h" })
                ?? service.windows.first
            secondaryWindow =
                service.windows.first(where: { $0.title == "On-demand" })
                ?? service.windows.first(where: { $0.title == "7d" })
        case .codex, .claude:
            primaryWindow = service.windows.first(where: { $0.title == "5h" })
            secondaryWindow = service.windows.first(where: { $0.title == "7d" })
        }

        guard let primaryWindow else {
            return nil
        }

        switch mode {
        case .fiveHourOnly:
            return primaryWindow.percentText
        case .fiveHourAndWeekly:
            guard let secondaryWindow else {
                return primaryWindow.percentText
            }

            return "\(primaryWindow.percentText)/\(secondaryWindow.percentText)"
        }
    }

    private static func loadMenuBarDisplayMode(from userDefaults: UserDefaults) -> MenuBarDisplayMode {
        guard
            let rawValue = userDefaults.string(forKey: menuBarDisplayModeDefaultsKey),
            let mode = MenuBarDisplayMode(rawValue: rawValue)
        else {
            return .fiveHourOnly
        }

        return mode
    }
}
