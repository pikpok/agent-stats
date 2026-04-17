import Foundation

struct CodexUsageProvider: Sendable {
    private let authURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/auth.json")
    private let sessionsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions")
    private let liveFetcher = CodexAppServerRateLimitFetcher()

    func fetch() async -> ServiceSnapshot {
        let auth = loadAuthStatus()
        guard auth.isLoggedIn else {
            return ServiceSnapshot(
                service: .codex,
                displayName: "Codex",
                accountDescription: nil,
                state: .loggedOut,
                windows: [],
                notices: ["Sign in with `codex login` to populate subscription usage."],
                sourceDescription: "Codex auth state",
                capturedAt: nil
            )
        }

        if let liveSnapshot = await liveFetcher.fetch(accountDescription: auth.accountDescription) {
            return liveSnapshot
        }

        guard let snapshot = latestSnapshot() else {
            return ServiceSnapshot(
                service: .codex,
                displayName: "Codex",
                accountDescription: auth.accountDescription,
                state: .stale,
                windows: [],
                notices: [
                    "The live Codex rate-limit fetch was unavailable.",
                    "Run Codex once to capture a fallback session snapshot.",
                ],
                sourceDescription: "Latest token_count event from ~/.codex/sessions",
                capturedAt: nil
            )
        }

        var notices: [String] = ["Live Codex rate-limit fetch was unavailable, so the app fell back to the latest session snapshot."]
        let state: ServiceState
        if let capturedAt = snapshot.capturedAt, Date().timeIntervalSince(capturedAt) > 12 * 60 * 60 {
            state = .stale
            notices.append("The latest Codex snapshot is older than 12 hours.")
        } else {
            state = .ready
        }

        if let planType = snapshot.planType, !planType.isEmpty {
            notices.append("Plan type: \(planType)")
        }

        return ServiceSnapshot(
            service: .codex,
            displayName: "Codex",
            accountDescription: auth.accountDescription,
            state: state,
            windows: snapshot.windows,
            notices: notices,
            sourceDescription: "Latest token_count event from ~/.codex/sessions",
            capturedAt: snapshot.capturedAt
        )
    }

    private func loadAuthStatus() -> CodexAuthStatus {
        guard
            let data = try? Data(contentsOf: authURL),
            let payload = try? JSONDecoder().decode(CodexAuthPayload.self, from: data)
        else {
            return CodexAuthStatus(isLoggedIn: false, accountDescription: nil)
        }

        let authMode = payload.authMode.map { $0 == "chatgpt" ? "ChatGPT login" : $0.capitalized }
        return CodexAuthStatus(isLoggedIn: true, accountDescription: authMode)
    }

    private func latestSnapshot() -> ParsedCodexSnapshot? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let files = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "jsonl" else {
                return nil
            }

            return url
        }
        .sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }

        for url in files.prefix(25) {
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }

            if let snapshot = Self.parseLatestSnapshot(from: contents) {
                return snapshot
            }
        }

        return nil
    }

    static func parseLatestSnapshot(from contents: String) -> ParsedCodexSnapshot? {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for rawLine in contents.split(separator: "\n").reversed() {
            guard let data = String(rawLine).data(using: .utf8) else {
                continue
            }

            guard
                let envelope = try? decoder.decode(CodexSessionEnvelope.self, from: data),
                envelope.type == "event_msg",
                envelope.payload?.type == "token_count",
                let rateLimits = envelope.payload?.rateLimits
            else {
                continue
            }

            let windows = [
                rateLimits.primary.map {
                    UsageWindow(
                        key: "codex_primary",
                        title: label(for: $0.windowMinutes, fallback: "Primary"),
                        detail: "Rolling limit",
                        usedPercent: $0.usedPercent,
                        resetsAt: Date(timeIntervalSince1970: $0.resetsAt)
                    )
                },
                rateLimits.secondary.map {
                    UsageWindow(
                        key: "codex_secondary",
                        title: label(for: $0.windowMinutes, fallback: "Secondary"),
                        detail: "Longer rolling limit",
                        usedPercent: $0.usedPercent,
                        resetsAt: Date(timeIntervalSince1970: $0.resetsAt)
                    )
                },
            ].compactMap { $0 }

            return ParsedCodexSnapshot(
                capturedAt: formatter.date(from: envelope.timestamp),
                planType: rateLimits.planType,
                windows: windows
            )
        }

        return nil
    }

    fileprivate static func label(for windowMinutes: Int, fallback: String) -> String {
        switch windowMinutes {
        case 300:
            return "5h"
        case 10080:
            return "7d"
        default:
            return fallback
        }
    }
}

private struct CodexAuthStatus {
    let isLoggedIn: Bool
    let accountDescription: String?
}

private struct CodexAuthPayload: Decodable {
    let authMode: String?

    enum CodingKeys: String, CodingKey {
        case authMode = "auth_mode"
    }
}

struct ParsedCodexSnapshot: Sendable {
    let capturedAt: Date?
    let planType: String?
    let windows: [UsageWindow]

    init(capturedAt: Date?, planType: String?, windows: [UsageWindow]) {
        self.capturedAt = capturedAt
        self.planType = planType
        self.windows = windows
    }

    init?(appServerResponse: CodexAppServerRateLimitsResponse) {
        let preferredSnapshot = appServerResponse.rateLimitsByLimitId?["codex"] ?? appServerResponse.rateLimits
        let windows = [
            preferredSnapshot.primary.map {
                UsageWindow(
                    key: "codex_primary",
                    title: CodexUsageProvider.label(for: $0.windowDurationMins ?? 0, fallback: "Primary"),
                    detail: "Rolling limit",
                    usedPercent: Double($0.usedPercent),
                    resetsAt: $0.resetsAt.map { Date(timeIntervalSince1970: $0) }
                )
            },
            preferredSnapshot.secondary.map {
                UsageWindow(
                    key: "codex_secondary",
                    title: CodexUsageProvider.label(for: $0.windowDurationMins ?? 0, fallback: "Secondary"),
                    detail: "Longer rolling limit",
                    usedPercent: Double($0.usedPercent),
                    resetsAt: $0.resetsAt.map { Date(timeIntervalSince1970: $0) }
                )
            },
        ].compactMap { $0 }

        guard !windows.isEmpty else {
            return nil
        }

        self.init(capturedAt: Date(), planType: preferredSnapshot.planType, windows: windows)
    }
}

private struct CodexSessionEnvelope: Decodable {
    let timestamp: String
    let type: String
    let payload: CodexPayload?
}

private struct CodexPayload: Decodable {
    let type: String?
    let rateLimits: CodexRateLimits?

    enum CodingKeys: String, CodingKey {
        case type
        case rateLimits = "rate_limits"
    }
}

private struct CodexRateLimits: Decodable {
    let primary: CodexWindow?
    let secondary: CodexWindow?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case planType = "plan_type"
    }
}

private struct CodexWindow: Decodable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: TimeInterval

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}
