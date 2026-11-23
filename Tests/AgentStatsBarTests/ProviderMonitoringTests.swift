import Foundation
import Testing
@testable import AgentStatsBar

@Suite @MainActor
struct ProviderMonitoringTests {
    @Test
    func switchesPersistIndependentlyAcrossModelInstances() async {
        let fixture = MonitoringFixture()
        let model = fixture.makeModel()
        #expect(model.enabledServices == Set(ServiceKind.allCases))
        #expect(model.menuBarDisplayMode == .fiveHourOnly)

        model.menuBarDisplayMode = .fiveHourAndWeekly
        model.setMonitoring(false, for: .codex)
        model.setMonitoring(false, for: .cursor)
        let reopened = fixture.makeModel()
        #expect(reopened.enabledServices == [.claude])
        #expect(reopened.menuBarDisplayMode == .fiveHourAndWeekly)

        reopened.setMonitoring(true, for: .cursor)
        await reopened.waitForRefresh()
        #expect(fixture.makeModel().enabledServices == [.claude, .cursor])
        #expect(fixture.calls == [.cursor: 1])
    }

    @Test(arguments: ServiceKind.allCases)
    func refreshAndSnapshotCLISkipDisabledProvider(_ disabled: ServiceKind) async throws {
        let fixture = MonitoringFixture()
        let model = fixture.makeModel()
        model.setMonitoring(false, for: disabled)
        let expected = ServiceKind.allCases.filter { $0 != disabled }

        await model.refresh()
        #expect(model.snapshot.services.map(\.service) == expected)
        #expect(model.menuBarItems.map(\.service) == expected)
        #expect(model.shouldShowMenuBarSymbol == expected.contains(.claude))
        #expect(model.canInstallClaudeHelper == expected.contains(.claude))

        let snapshot = try await fixture.cliSnapshot()
        #expect(snapshot.services.map(\.service) == expected)
        #expect(fixture.calls == Dictionary(uniqueKeysWithValues: expected.map { ($0, 2) }))
    }

    @Test
    func allOffStaysIdleAcrossLaunchesAndCanResumeOneProvider() async throws {
        let fixture = MonitoringFixture()
        let model = fixture.makeModel()
        for service in ServiceKind.allCases {
            model.setMonitoring(false, for: service)
        }

        let reopened = fixture.makeModel()
        await reopened.refresh()
        let cliSnapshot = try await fixture.cliSnapshot()
        #expect(cliSnapshot.services.isEmpty)
        #expect(reopened.enabledServices.isEmpty)
        #expect(fixture.calls.isEmpty)
        #expect(reopened.snapshot.services.isEmpty)
        #expect(reopened.menuBarTitle == "Agent Stats")
        #expect(!reopened.isRefreshing)
        #expect(!reopened.shouldShowMenuBarSymbol)
        #expect(!reopened.canInstallClaudeHelper)

        reopened.setMonitoring(true, for: .codex)
        await reopened.waitForRefresh()
        #expect(fixture.calls == [.codex: 1])
        #expect(reopened.snapshot.services.map(\.service) == [.codex])
        #expect(reopened.menuBarTitle == "Co 1%")
    }

    @Test
    func pollingContinuesAfterDisablingAStuckProvider() async throws {
        let (release, signalRelease) = AsyncStream<Void>.makeStream()
        let waitForRelease = Task { for await _ in release {} }
        defer { signalRelease.finish() }
        let fixture = MonitoringFixture { service, _ in
            if service == .claude {
                // A Keychain call can keep waiting after its task is cancelled.
                await waitForRelease.value
            }
        }
        let model = fixture.makeModel()
        model.startPolling(every: .milliseconds(10))

        try #require(try await waitUntil {
            fixture.calls[.claude] == 1 && model.snapshot.services.map(\.service) == [.codex, .cursor]
        })
        model.setMonitoring(false, for: .claude)
        let callsAtDisable = fixture.calls

        #expect(try await waitUntil {
            [.codex, .cursor].allSatisfy { service in
                fixture.calls[service, default: 0] > callsAtDisable[service, default: 0]
            }
        }, "Both healthy providers should poll again while the cancelled Claude fetch is still blocked")
    }

    private func waitUntil(_ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func lateCompletionCannotRestoreDisabledUsageOrReplaceNewUsage(reenable: Bool) async {
        let (started, signalStart) = AsyncStream<Void>.makeStream()
        let (release, signalRelease) = AsyncStream<Void>.makeStream()
        let waitForRelease = Task { for await _ in release {} }
        let fixture = MonitoringFixture { service, attempt in
            if service == .claude && attempt == 2 {
                signalStart.finish()
                // Simulate a provider that returns an old result even after cancellation.
                await waitForRelease.value
                #expect(Task.isCancelled)
            }
        }
        let model = fixture.makeModel()
        await model.refresh()
        #expect(model.shouldShowMenuBarSymbol)

        let refresh = Task { await model.refresh() }
        for await _ in started {}
        model.setMonitoring(false, for: .claude)
        #expect(model.snapshot.services.map(\.service) == [.codex, .cursor])
        #expect(model.menuBarItems.map(\.service) == [.codex, .cursor])
        #expect(!model.shouldShowMenuBarSymbol)
        #expect(!model.canInstallClaudeHelper)

        if reenable {
            model.setMonitoring(true, for: .claude)
            await model.waitForRefresh()
        }
        signalRelease.finish()
        await refresh.value

        #expect(fixture.calls == [.codex: 2, .claude: reenable ? 3 : 2, .cursor: 2])
        let expected = reenable ? ServiceKind.allCases : [.codex, .cursor]
        #expect(model.snapshot.services.map(\.service) == expected)
        #expect(model.menuBarItems.filter { $0.service != .claude }.map(\.valueText) == ["2%", "2%"])
        #expect(model.menuBarItems.first { $0.service == .claude }?.valueText == (reenable ? "3%" : nil))
        #expect(!model.isRefreshing)
    }
}

@MainActor
private final class MonitoringFixture {
    private let defaults = MemoryDefaults()
    private let beforeReturning: (ServiceKind, Int) async -> Void
    private(set) var calls: [ServiceKind: Int] = [:]

    init(beforeReturning: @escaping (ServiceKind, Int) async -> Void = { _, _ in }) {
        self.beforeReturning = beforeReturning
    }

    func makeModel() -> AppModel {
        AppModel(
            userDefaults: defaults,
            monitoringPreferences: MonitoringPreferences(defaults: defaults),
            fetchUsage: fetch
        )
    }

    func cliSnapshot() async throws -> AppSnapshot {
        var output = ""
        await SnapshotCLI.dumpSnapshot(model: makeModel()) { output = $0 }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppSnapshot.self, from: Data(output.utf8))
    }

    private func fetch(_ service: ServiceKind) async -> ProviderUsage {
        let attempt = calls[service, default: 0] + 1
        calls[service] = attempt
        await beforeReturning(service, attempt)
        let snapshot = ServiceSnapshot(
            service: service, displayName: service.rawValue, accountDescription: nil,
            state: service == .claude ? .stale : .ready,
            windows: [UsageWindow(key: "test", title: "5h", detail: nil, usedPercent: Double(attempt), resetsAt: nil)],
            notices: [], sourceDescription: "Fixture", capturedAt: nil
        )
        return ProviderUsage(snapshot: snapshot, claudeHelperStatus: service == .claude ? .notInstalled : nil)
    }
}

// Exercise the production preference keys without writing a preferences domain on the test Mac.
private final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]

    override func object(forKey name: String) -> Any? { values[name] }
    override func string(forKey name: String) -> String? { values[name] as? String }
    override func set(_ value: Any?, forKey name: String) { values[name] = value }
    override func set(_ value: Bool, forKey name: String) { values[name] = value }
}
