import Foundation

struct ProviderUsage: Sendable {
    let snapshot: ServiceSnapshot
    let claudeHelperStatus: ClaudeHelperInstallStatus?

    @concurrent
    static func fetch(_ service: ServiceKind) async -> ProviderUsage? {
        guard !Task.isCancelled else { return nil }

        let snapshot: ServiceSnapshot?
        var helperStatus: ClaudeHelperInstallStatus?
        switch service {
        case .codex:
            snapshot = await CodexUsageProvider().fetch()
        case .claude:
            let status = ClaudeStatuslineHelperInstaller().status()
            helperStatus = status
            snapshot = await ClaudeUsageProvider().fetch(helperStatus: status)
        case .cursor:
            snapshot = await CursorUsageProvider().fetch()
        }
        return snapshot.map { ProviderUsage(snapshot: $0, claudeHelperStatus: helperStatus) }
    }
}
