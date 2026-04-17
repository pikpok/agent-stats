import Foundation

struct ClaudeDesktopUsageFetcher: Sendable {
    private let cookieReader = ClaudeDesktopCookieReader()

    func fetch(accountDescription: String?) async -> ServiceSnapshot? {
        guard let session = cookieReader.loadClaudeSession() else {
            return nil
        }

        guard let response = await requestUsage(session: session) else {
            return nil
        }

        let windows = response.windows
        guard !windows.isEmpty else {
            return nil
        }

        var notices: [String] = []
        if let extraUsage = response.extraUsage {
            if extraUsage.isEnabled, let monthlyLimit = extraUsage.monthlyLimit, let usedCredits = extraUsage.usedCredits {
                notices.append("Extra usage: $\(Int(usedCredits.rounded())) of $\(Int(monthlyLimit.rounded())) spent this month.")
            } else if extraUsage.isEnabled {
                notices.append("Extra usage billing is enabled.")
            }
        }

        return ServiceSnapshot(
            service: .claude,
            displayName: "Claude Code",
            accountDescription: accountDescription,
            state: .ready,
            windows: windows,
            notices: notices,
            sourceDescription: "Claude desktop web session",
            capturedAt: Date()
        )
    }

    private func requestUsage(session: ClaudeDesktopSession) async -> ClaudeDesktopUsageResponse? {
        guard
            let organizationUUID = session.organizationUUID,
            let url = URL(string: "https://claude.ai/api/organizations/\(organizationUUID)/usage")
        else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "Referer")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) ClaudeDesktop/1.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(organizationUUID, forHTTPHeaderField: "X-Organization-Uuid")
        if let deviceID = session.deviceID, !deviceID.isEmpty {
            request.setValue(deviceID, forHTTPHeaderField: "Anthropic-Device-Id")
        }

        let cookieHeader = HTTPCookie.requestHeaderFields(with: session.cookies)["Cookie"]
        if let cookieHeader {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8

        let session = URLSession(configuration: configuration)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            let decoder = JSONDecoder()
            return try decoder.decode(ClaudeDesktopUsageResponse.self, from: data)
        } catch {
            return nil
        }
    }
}

struct ClaudeDesktopUsageResponse: Decodable, Sendable {
    let fiveHour: ClaudeDesktopUsageWindow?
    let sevenDay: ClaudeDesktopUsageWindow?
    let sevenDayOpus: ClaudeDesktopUsageWindow?
    let sevenDaySonnet: ClaudeDesktopUsageWindow?
    let sevenDayCowork: ClaudeDesktopUsageWindow?
    let extraUsage: ClaudeExtraUsage?
    let windowsByCode: [String: ClaudeDesktopUsageWindow]

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayCowork = "seven_day_cowork"
        case extraUsage = "extraUsage"
        case extraUsageAlt = "extra_usage"
        case windows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try container.decodeIfPresent(ClaudeDesktopUsageWindow.self, forKey: .fiveHour)
        sevenDay = try container.decodeIfPresent(ClaudeDesktopUsageWindow.self, forKey: .sevenDay)
        sevenDayOpus = try container.decodeIfPresent(ClaudeDesktopUsageWindow.self, forKey: .sevenDayOpus)
        sevenDaySonnet = try container.decodeIfPresent(ClaudeDesktopUsageWindow.self, forKey: .sevenDaySonnet)
        sevenDayCowork = try container.decodeIfPresent(ClaudeDesktopUsageWindow.self, forKey: .sevenDayCowork)
        extraUsage =
            (try? container.decodeIfPresent(ClaudeExtraUsage.self, forKey: .extraUsage))
            ?? (try? container.decodeIfPresent(ClaudeExtraUsage.self, forKey: .extraUsageAlt))
        windowsByCode = try container.decodeIfPresent([String: ClaudeDesktopUsageWindow].self, forKey: .windows) ?? [:]
    }

    var windows: [UsageWindow] {
        let direct = [
            windowFromDirectKey(key: "claude_five_hour", fallbackTitle: "5h", fallbackDetail: "Current session", direct: fiveHour),
            windowFromDirectKey(key: "claude_seven_day", fallbackTitle: "7d", fallbackDetail: "Current week", direct: sevenDay),
            windowFromDirectKey(key: "claude_seven_day_opus", fallbackTitle: "7d Opus", fallbackDetail: "Current week (Opus)", direct: sevenDayOpus),
            windowFromDirectKey(key: "claude_seven_day_sonnet", fallbackTitle: "7d Sonnet", fallbackDetail: "Current week (Sonnet)", direct: sevenDaySonnet),
            windowFromDirectKey(key: "claude_seven_day_cowork", fallbackTitle: "7d Cowork", fallbackDetail: "Current week (Cowork)", direct: sevenDayCowork),
        ].compactMap { $0 }

        if !direct.isEmpty {
            return direct
        }

        return [
            windowFromWindowMap(code: "5h", fallbackKey: "claude_five_hour", fallbackTitle: "5h", fallbackDetail: "Current session"),
            windowFromWindowMap(code: "7d", fallbackKey: "claude_seven_day", fallbackTitle: "7d", fallbackDetail: "Current week"),
        ].compactMap { $0 }
    }

    private func windowFromDirectKey(
        key: String,
        fallbackTitle: String,
        fallbackDetail: String?,
        direct: ClaudeDesktopUsageWindow?
    ) -> UsageWindow? {
        guard let direct else {
            return nil
        }

        return UsageWindow(
            key: key,
            title: fallbackTitle,
            detail: direct.displayTitle ?? fallbackDetail,
            usedPercent: direct.displayPercent,
            resetsAt: direct.resetDate
        )
    }

    private func windowFromWindowMap(
        code: String,
        fallbackKey: String,
        fallbackTitle: String,
        fallbackDetail: String?
    ) -> UsageWindow? {
        guard let window = windowsByCode[code] else {
            return nil
        }

        return UsageWindow(
            key: fallbackKey,
            title: fallbackTitle,
            detail: window.displayTitle ?? fallbackDetail,
            usedPercent: window.displayPercent,
            resetsAt: window.resetDate
        )
    }
}

struct ClaudeDesktopUsageWindow: Decodable, Sendable {
    let title: String?
    let utilization: Double?
    let usedPercentage: Double?
    let resetsAt: ClaudeDesktopResetDate?

    enum CodingKeys: String, CodingKey {
        case title
        case utilization
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        utilization = try container.decodeIfPresent(Double.self, forKey: .utilization)
        usedPercentage = try container.decodeIfPresent(Double.self, forKey: .usedPercentage)

        if let dateString = try? container.decodeIfPresent(String.self, forKey: .resetsAt) {
            resetsAt = .iso8601(dateString)
        } else if let epoch = try? container.decodeIfPresent(Double.self, forKey: .resetsAt) {
            resetsAt = .unix(epoch)
        } else if let epoch = try? container.decodeIfPresent(Int.self, forKey: .resetsAt) {
            resetsAt = .unix(Double(epoch))
        } else {
            resetsAt = nil
        }
    }

    var displayTitle: String? {
        guard let title, !title.isEmpty else {
            return nil
        }
        return title
    }

    var displayPercent: Double {
        if let usedPercentage {
            return usedPercentage
        }

        if let utilization {
            return utilization <= 1.0 ? utilization * 100 : utilization
        }

        return 0
    }

    var resetDate: Date? {
        resetsAt?.date
    }
}

enum ClaudeDesktopResetDate: Sendable {
    case unix(Double)
    case iso8601(String)

    var date: Date? {
        switch self {
        case let .unix(seconds):
            return Date(timeIntervalSince1970: seconds)
        case let .iso8601(value):
            return parseClaudeDesktopDate(value)
        }
    }
}

private func parseClaudeDesktopDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    if let date = formatter.date(from: value) {
        return date
    }

    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}
