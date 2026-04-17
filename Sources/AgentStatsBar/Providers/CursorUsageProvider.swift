import Foundation

struct CursorUsageProvider: Sendable {
    func fetch() async -> ServiceSnapshot {
        guard let session = CursorAuthReader.loadSession() else {
            return ServiceSnapshot(
                service: .cursor,
                displayName: "Cursor",
                accountDescription: nil,
                state: .loggedOut,
                windows: [],
                notices: [
                    "Sign in to Cursor so `cursorAuth/accessToken` is stored in Cursor's local state database.",
                ],
                sourceDescription: "Cursor session from ~/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
                capturedAt: nil
            )
        }

        let sessionForRequests = session

        do {
            let summaryResult = try await Self.performGET(
                url: Self.summaryURL,
                session: sessionForRequests
            )

            if summaryResult.statusCode == 200 {
                if let parsed = CursorUsageSummaryParser.parse(data: summaryResult.data), !parsed.windows.isEmpty {
                    var notices = parsed.notices
                    if let end = parsed.billingCycleEnd {
                        notices.append("Cycle ends \(end.formatted(date: .abbreviated, time: .omitted)).")
                    }

                    return snapshot(
                        for: sessionForRequests,
                        state: .ready,
                        windows: parsed.windows,
                        notices: notices,
                        capturedAt: Date(),
                        sourceDescription: "Cursor usage summary (GET /api/usage-summary)"
                    )
                }
            }

            let usageResult = try await Self.performGET(
                url: Self.usageURL(userId: sessionForRequests.userId),
                session: sessionForRequests
            )

            guard usageResult.statusCode == 200 else {
                if summaryResult.statusCode == 401 || summaryResult.statusCode == 403 || usageResult.statusCode == 401
                    || usageResult.statusCode == 403
                {
                    return ServiceSnapshot(
                        service: .cursor,
                        displayName: "Cursor",
                        accountDescription: accountSummary(for: sessionForRequests),
                        state: .loggedOut,
                        windows: [],
                        notices: [
                            "Cursor rejected the stored session. Sign in again from Cursor, then retry.",
                        ],
                        sourceDescription: "Cursor dashboard APIs",
                        capturedAt: nil
                    )
                }

                return snapshot(
                    for: sessionForRequests,
                    state: .error,
                    windows: [],
                    notices: [
                        "Usage summary HTTP \(summaryResult.statusCode), usage HTTP \(usageResult.statusCode).",
                    ],
                    capturedAt: nil,
                    sourceDescription: "Cursor dashboard APIs"
                )
            }

            let parsed = CursorUsageJSONParser.usageWindows(from: usageResult.data)

            if parsed.windows.isEmpty {
                return snapshot(
                    for: sessionForRequests,
                    state: .stale,
                    windows: [],
                    notices: [
                        "Could not read plan summary or legacy usage fields.",
                        "The Cursor API response shape may have changed.",
                    ],
                    capturedAt: Date(),
                    sourceDescription: "Cursor dashboard APIs (fallback)"
                )
            }

            var notices: [String] = []
            if let cycle = parsed.cycleStart {
                notices.append("Billing cycle starts \(cycle.formatted(date: .abbreviated, time: .shortened)).")
            }
            notices.append("Showing legacy meter — usage summary was unavailable or incomplete.")

            return snapshot(
                for: sessionForRequests,
                state: .ready,
                windows: parsed.windows,
                notices: notices,
                capturedAt: Date(),
                sourceDescription: "Cursor dashboard (GET /api/usage, legacy)"
            )
        } catch {
            return snapshot(
                for: sessionForRequests,
                state: .error,
                windows: [],
                notices: [error.localizedDescription],
                capturedAt: nil,
                sourceDescription: "Cursor dashboard APIs"
            )
        }
    }

    private static let summaryURL = URL(string: "https://cursor.com/api/usage-summary")!

    private static func usageURL(userId: String) -> URL {
        var components = URLComponents(string: "https://cursor.com/api/usage")!
        components.queryItems = [URLQueryItem(name: "user", value: userId)]
        return components.url!
    }

    private struct HTTPResult: Sendable {
        let statusCode: Int
        let data: Data
    }

    private static func performGET(url: URL, session: CursorAuthSession) async throws -> HTTPResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("https://cursor.com/dashboard", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Cursor/1.0 Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            "WorkosCursorSessionToken=\(session.workosSessionCookieValue)",
            forHTTPHeaderField: "Cookie"
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15

        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return HTTPResult(statusCode: status, data: data)
    }

    private func snapshot(
        for session: CursorAuthSession,
        state: ServiceState,
        windows: [UsageWindow],
        notices: [String],
        capturedAt: Date?,
        sourceDescription: String
    ) -> ServiceSnapshot {
        ServiceSnapshot(
            service: .cursor,
            displayName: "Cursor",
            accountDescription: accountSummary(for: session),
            state: state,
            windows: windows,
            notices: notices,
            sourceDescription: sourceDescription,
            capturedAt: capturedAt
        )
    }

    private func accountSummary(for session: CursorAuthSession) -> String? {
        [
            session.membershipDescription,
            session.accountEmail,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
        .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
