import Foundation

struct ClaudeUsageProvider: Sendable {
    private let helperInstaller: ClaudeStatuslineHelperInstaller
    private let desktopFetcher = ClaudeDesktopUsageFetcher()

    init(helperInstaller: ClaudeStatuslineHelperInstaller) {
        self.helperInstaller = helperInstaller
    }

    func fetch() async -> ServiceSnapshot {
        let helperStatus = helperInstaller.status()
        let credentials = loadCredentials()

        guard let credentials else {
            return ServiceSnapshot(
                service: .claude,
                displayName: "Claude Code",
                accountDescription: nil,
                state: .loggedOut,
                windows: [],
                notices: ["Sign in with Claude Code to expose local subscription metadata."],
                sourceDescription: "Claude keychain credentials",
                capturedAt: nil
            )
        }

        let accountDescription = [
            credentials.subscriptionType?.replacingOccurrences(of: "_", with: " ").capitalized,
            credentials.rateLimitTier?.replacingOccurrences(of: "_", with: " "),
        ]
        .compactMap { $0 }
        .joined(separator: " / ")

        if let desktopSnapshot = await desktopFetcher.fetch(
            accountDescription: accountDescription.isEmpty ? nil : accountDescription
        ) {
            return desktopSnapshot
        }

        return loadFallbackSnapshot(
            credentials: credentials,
            accountDescription: accountDescription,
            helperStatus: helperStatus
        )
    }

    private func loadFallbackSnapshot(
        credentials: ClaudeOAuthDetails,
        accountDescription: String,
        helperStatus: ClaudeHelperInstallStatus
    ) -> ServiceSnapshot {
        guard let cache = loadUsageCache() else {
            return ServiceSnapshot(
                service: .claude,
                displayName: "Claude Code",
                accountDescription: accountDescription.isEmpty ? nil : accountDescription,
                state: helperStatus == .installed ? .stale : .needsSetup,
                windows: [],
                notices: setupNotice(for: helperStatus),
                sourceDescription: "Claude statusline helper cache",
                capturedAt: nil
            )
        }

        let windows = [
            cache.rateLimits?.fiveHour.map {
                UsageWindow(
                    key: "claude_five_hour",
                    title: "5h",
                    detail: "Current session",
                    usedPercent: $0.usedPercentage,
                    resetsAt: $0.resetDate
                )
            },
            cache.rateLimits?.sevenDay.map {
                UsageWindow(
                    key: "claude_seven_day",
                    title: "7d",
                    detail: "Current week",
                    usedPercent: $0.usedPercentage,
                    resetsAt: $0.resetDate
                )
            },
            cache.rateLimits?.sevenDaySonnet.map {
                UsageWindow(
                    key: "claude_seven_day_sonnet",
                    title: "7d Sonnet",
                    detail: "Sonnet only",
                    usedPercent: $0.usedPercentage,
                    resetsAt: $0.resetDate
                )
            },
        ].compactMap { $0 }

        var notices: [String] = []
        if let extraUsage = cache.rateLimits?.extraUsage {
            if extraUsage.isEnabled, let monthlyLimit = extraUsage.monthlyLimit, let usedCredits = extraUsage.usedCredits {
                notices.append("Extra usage: $\(Int(usedCredits.rounded())) of $\(Int(monthlyLimit.rounded())) spent this month.")
            } else if extraUsage.isEnabled {
                notices.append("Extra usage billing is enabled.")
            }
        }

        let state: ServiceState
        if !cache.isPlausiblyCurrent {
            state = .stale
            notices.insert("The Claude helper cache is stale. Its reset timestamps are already in the past.", at: 0)
        } else if let capturedAt = cache.capturedAt, Date().timeIntervalSince(capturedAt) > 12 * 60 * 60 {
            state = .stale
            notices.insert("The latest Claude snapshot is older than 12 hours.", at: 0)
        } else {
            state = .ready
        }

        if state != .ready {
            notices.append("Desktop-session fetch was unavailable, so the app fell back to Claude's local statusline cache.")
        }

        return ServiceSnapshot(
            service: .claude,
            displayName: "Claude Code",
            accountDescription: accountDescription.isEmpty ? nil : accountDescription,
            state: state,
            windows: windows,
            notices: notices,
            sourceDescription: "Claude statusline helper cache",
            capturedAt: cache.capturedAt
        )
    }

    private func setupNotice(for status: ClaudeHelperInstallStatus) -> [String] {
        switch status {
        case .installed:
            return ["Open Claude Code and send one message. The helper captures `rate_limits` from Claude's supported statusline JSON."]
        case .notInstalled, .notConfigured:
            return ["Install the Claude helper to cache `rate_limits` locally without another login."]
        case .customStatusLine:
            return ["A custom Claude status line is already configured. Wire ~/.claude/agent-stats/claude_statusline.py into it manually to expose usage here."]
        }
    }

    private func loadCredentials() -> ClaudeOAuthDetails? {
        guard
            let secret = KeychainReader.readGenericPassword(service: "Claude Code-credentials"),
            let data = secret.data(using: .utf8),
            let payload = try? JSONDecoder().decode(ClaudeCredentialsPayload.self, from: data)
        else {
            return nil
        }

        return payload.claudeAiOauth
    }

    private func loadUsageCache() -> ClaudeUsageCache? {
        let url = ClaudeStatuslineHelperInstaller.cacheURL()
        guard
            let data = try? Data(contentsOf: url),
            let payload = try? JSONDecoder().decode(ClaudeUsageCache.self, from: data)
        else {
            return nil
        }

        return payload
    }
}

private struct ClaudeCredentialsPayload: Decodable {
    let claudeAiOauth: ClaudeOAuthDetails
}

struct ClaudeOAuthDetails: Decodable, Sendable {
    let accessToken: String?
    let subscriptionType: String?
    let rateLimitTier: String?

    enum CodingKeys: String, CodingKey {
        case accessToken
        case subscriptionType
        case rateLimitTier
    }
}

struct ClaudeUsageCache: Decodable, Sendable {
    let capturedAt: Date?
    let rateLimits: ClaudeRateLimits?

    enum CodingKeys: String, CodingKey {
        case capturedAt = "captured_at"
        case rateLimits = "rate_limits"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let epoch = try container.decodeIfPresent(TimeInterval.self, forKey: .capturedAt) {
            capturedAt = Date(timeIntervalSince1970: epoch)
        } else {
            capturedAt = nil
        }
        rateLimits = try container.decodeIfPresent(ClaudeRateLimits.self, forKey: .rateLimits)
    }

    var isPlausiblyCurrent: Bool {
        guard let capturedAt else {
            return false
        }

        let resetDates = [
            rateLimits?.fiveHour?.resetDate,
            rateLimits?.sevenDay?.resetDate,
            rateLimits?.sevenDaySonnet?.resetDate,
        ].compactMap { $0 }

        guard !resetDates.isEmpty else {
            return false
        }

        return resetDates.contains { $0.timeIntervalSince(capturedAt) > -300 }
    }
}

struct ClaudeRateLimits: Decodable, Sendable {
    let fiveHour: ClaudeRateLimitWindow?
    let sevenDay: ClaudeRateLimitWindow?
    let sevenDaySonnet: ClaudeRateLimitWindow?
    let extraUsage: ClaudeExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }
}

struct ClaudeRateLimitWindow: Decodable, Sendable {
    let usedPercentage: Double
    let resetsAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    var resetDate: Date? {
        guard let resetsAt else {
            return nil
        }
        return Date(timeIntervalSince1970: resetsAt)
    }
}

struct ClaudeExtraUsage: Decodable, Sendable {
    let isEnabled: Bool
    let monthlyLimit: Double?
    let usedCredits: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
    }
}
