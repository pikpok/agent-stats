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
    @Published private(set) var enabledServices: Set<ServiceKind>
    @Published private var refreshTasks: [ServiceKind: Task<Void, Never>] = [:]
    @Published private var helperStatus: ClaudeHelperInstallStatus?
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

    private let userDefaults: UserDefaults
    private let launchAtLoginManager: LaunchAtLoginManager
    private let monitoringPreferences: MonitoringPreferences
    private let fetchUsage: @Sendable (ServiceKind) async -> ProviderUsage?
    private var pollingTask: Task<Void, Never>?

    init(
        userDefaults: UserDefaults = .standard,
        launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager(),
        monitoringPreferences: MonitoringPreferences = MonitoringPreferences(),
        fetchUsage: @escaping @Sendable (ServiceKind) async -> ProviderUsage? = ProviderUsage.fetch
    ) {
        self.userDefaults = userDefaults
        self.launchAtLoginManager = launchAtLoginManager
        self.monitoringPreferences = monitoringPreferences
        self.enabledServices = monitoringPreferences.enabledServices
        self.fetchUsage = fetchUsage
        self.menuBarDisplayMode = Self.loadMenuBarDisplayMode(from: userDefaults)
    }

    deinit {
        pollingTask?.cancel()
    }

    var isRefreshing: Bool { !refreshTasks.isEmpty }

    var canInstallClaudeHelper: Bool {
        enabledServices.contains(.claude) && helperStatus?.canAttemptInstall == true
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
        shouldShowMenuBarSymbol ? "exclamationmark.circle" : "gauge.with.dots.needle.50percent"
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
        guard !enabledServices.isEmpty else { return }
        transientMessage = nil
        for service in enabledServices {
            startRefresh(for: service)
        }
    }

    func setMonitoring(_ enabled: Bool, for service: ServiceKind) {
        guard enabledServices.contains(service) != enabled else { return }
        monitoringPreferences.setEnabled(enabled, for: service)
        if enabled {
            enabledServices.insert(service)
            startRefresh(for: service)
            return
        }

        enabledServices.remove(service)
        refreshTasks.removeValue(forKey: service)?.cancel()
        let remaining = snapshot.services.filter { $0.service != service }
        snapshot = remaining.isEmpty ? .empty : AppSnapshot(fetchedAt: snapshot.fetchedAt, services: remaining)
        if service == .claude {
            helperStatus = nil
        }
    }

    func installClaudeHelper() {
        Task {
            guard canInstallClaudeHelper else { return }
            let result = ClaudeStatuslineHelperInstaller().install()
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

    func startPolling(every interval: Duration = .seconds(60)) {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshNow()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func refresh() async {
        refreshNow()
        await waitForRefresh()
    }

    func waitForRefresh() async {
        for task in refreshTasks.values {
            await task.value
        }
    }

    private func startRefresh(for service: ServiceKind) {
        guard refreshTasks[service] == nil else { return }
        refreshTasks[service] = Task {
            guard !Task.isCancelled else { return }
            let usage = await fetchUsage(service)
            // A cancelled request can finish after the same provider has been enabled again.
            guard !Task.isCancelled else { return }
            if let usage {
                var services = snapshot.services.filter { $0.service != service }
                services.append(usage.snapshot)
                services.sort { $0.service.sortOrder < $1.service.sortOrder }
                snapshot = AppSnapshot(fetchedAt: Date(), services: services)
                if service == .claude {
                    helperStatus = usage.claudeHelperStatus
                }
            }
            refreshTasks[service] = nil
        }
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
        case .codex:
            let fiveHourWindow = service.windows.first(where: { $0.title == "5h" })
            let weeklyWindow = service.windows.first(where: { $0.title == "7d" })

            primaryWindow = fiveHourWindow ?? weeklyWindow ?? service.windows.first
            secondaryWindow = fiveHourWindow == nil ? nil : weeklyWindow
        case .claude:
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
