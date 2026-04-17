import Foundation
import Testing
@testable import AgentStatsBar

@Test
func codexParserPicksLatestTokenCountEvent() throws {
    let jsonl = """
    {"timestamp":"2026-01-21T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":12.0,"window_minutes":300,"resets_at":1769000000},"secondary":{"used_percent":5.0,"window_minutes":10080,"resets_at":1769580000},"plan_type":"plus"}}}
    {"timestamp":"2026-01-21T11:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":54.0,"window_minutes":300,"resets_at":1769002696},"secondary":{"used_percent":16.0,"window_minutes":10080,"resets_at":1769589496},"plan_type":"plus"}}}
    """

    let snapshot = try #require(CodexUsageProvider.parseLatestSnapshot(from: jsonl))

    #expect(snapshot.planType == "plus")
    #expect(snapshot.windows.count == 2)
    #expect(snapshot.windows[0].title == "5h")
    #expect(Int(snapshot.windows[0].usedPercent.rounded()) == 54)
    #expect(snapshot.windows[1].title == "7d")
    #expect(Int(snapshot.windows[1].usedPercent.rounded()) == 16)
}

@Test
func codexAppServerRateLimitResponseDecodesLiveShape() throws {
    let payload = """
    {
      "rateLimits": {
        "limitId": "codex",
        "limitName": null,
        "primary": {
          "usedPercent": 8,
          "windowDurationMins": 300,
          "resetsAt": 1774883900
        },
        "secondary": {
          "usedPercent": 22,
          "windowDurationMins": 10080,
          "resetsAt": 1775419382
        },
        "credits": {
          "hasCredits": true,
          "unlimited": false,
          "balance": "250"
        },
        "planType": "plus"
      },
      "rateLimitsByLimitId": {
        "codex": {
          "limitId": "codex",
          "limitName": null,
          "primary": {
            "usedPercent": 8,
            "windowDurationMins": 300,
            "resetsAt": 1774883900
          },
          "secondary": {
            "usedPercent": 22,
            "windowDurationMins": 10080,
            "resetsAt": 1775419382
          },
          "credits": {
            "hasCredits": true,
            "unlimited": false,
            "balance": "250"
          },
          "planType": "plus"
        }
      }
    }
    """

    let response = try JSONDecoder().decode(CodexAppServerRateLimitsResponse.self, from: Data(payload.utf8))
    let snapshot = try #require(ParsedCodexSnapshot(appServerResponse: response))

    #expect(snapshot.planType == "plus")
    #expect(snapshot.windows.count == 2)
    #expect(snapshot.windows[0].title == "5h")
    #expect(Int(snapshot.windows[0].usedPercent.rounded()) == 8)
    #expect(snapshot.windows[1].title == "7d")
    #expect(Int(snapshot.windows[1].usedPercent.rounded()) == 22)
}

@Test
func codexAppServerRateLimitResponseRecoversEmbeddedWhamUsageBodyFromProliteDecodeError() throws {
    let message = #"failed to fetch codex rate limits from https://chatgpt.com/backend-api/wham/usage: unknown variant `prolite`, expected one of `free`, `plus`, `pro`, `business`, `enterprise` at line 1 column 123 body={"plan_type":"prolite","rate_limit":{"primary_window":{"used_percent":37.4,"limit_window_seconds":18000,"reset_at":1774883900},"secondary_window":{"used_percent":12.1,"limit_window_seconds":604800,"reset_at":1775419382}},"additional_rate_limits":[],"credits":{"has_credits":true,"unlimited":false,"balance":"250"}}"#

    let response = try #require(CodexAppServerRateLimitsResponse(recoveringAppServerErrorMessage: message))
    let snapshot = try #require(ParsedCodexSnapshot(appServerResponse: response))

    #expect(snapshot.planType == "prolite")
    #expect(snapshot.windows.count == 2)
    #expect(snapshot.windows[0].title == "5h")
    #expect(Int(snapshot.windows[0].usedPercent.rounded()) == 37)
    #expect(snapshot.windows[1].title == "7d")
    #expect(Int(snapshot.windows[1].usedPercent.rounded()) == 12)
}

@Test
func claudeUsageCacheDecodesRateLimits() throws {
    let payload = """
    {
      "captured_at": 1774815000,
      "rate_limits": {
        "five_hour": {
          "used_percentage": 31.8,
          "resets_at": 1774822200
        },
        "seven_day": {
          "used_percentage": 9.5,
          "resets_at": 1775330400
        },
        "seven_day_sonnet": {
          "used_percentage": 4.0,
          "resets_at": 1775330400
        },
        "extra_usage": {
          "is_enabled": true,
          "monthly_limit": 100.0,
          "used_credits": 17.0
        }
      }
    }
    """

    let cache = try JSONDecoder().decode(ClaudeUsageCache.self, from: Data(payload.utf8))

    #expect(Int(cache.rateLimits?.fiveHour?.usedPercentage.rounded() ?? 0) == 32)
    #expect(Int(cache.rateLimits?.sevenDay?.usedPercentage.rounded() ?? 0) == 10)
    #expect(cache.rateLimits?.extraUsage?.isEnabled == true)
    #expect(Int(cache.rateLimits?.extraUsage?.usedCredits ?? 0) == 17)
}

@Test
func claudeUsageCacheMarksPastResetsAsStale() throws {
    let payload = """
    {
      "captured_at": 1774815502,
      "rate_limits": {
        "five_hour": {
          "used_percentage": 66,
          "resets_at": 1774310400
        },
        "seven_day": {
          "used_percentage": 51,
          "resets_at": 1774512000
        }
      }
    }
    """

    let cache = try JSONDecoder().decode(ClaudeUsageCache.self, from: Data(payload.utf8))

    #expect(cache.isPlausiblyCurrent == false)
}

@Test
func claudeDesktopUsageResponseSupportsUtilizationShape() throws {
    let payload = """
    {
      "five_hour": {
        "title": "Current session",
        "utilization": 0.98,
        "resets_at": 1774818000
      },
      "seven_day": {
        "title": "Current week (all models)",
        "utilization": 0.22,
        "resets_at": 1775214000
      }
    }
    """

    let response = try JSONDecoder().decode(ClaudeDesktopUsageResponse.self, from: Data(payload.utf8))

    #expect(response.windows.count == 2)
    #expect(Int(response.windows[0].usedPercent.rounded()) == 98)
    #expect(Int(response.windows[1].usedPercent.rounded()) == 22)
}

@Test
func claudeDesktopUsageResponseSupportsOrganizationUsageShape() throws {
    let payload = """
    {
      "five_hour": {
        "utilization": 100.0,
        "resets_at": "2026-03-29T22:00:00.367721+00:00"
      },
      "seven_day": {
        "utilization": 22.0,
        "resets_at": "2026-04-02T09:00:00.367738+00:00"
      },
      "extra_usage": {
        "is_enabled": false,
        "monthly_limit": null,
        "used_credits": null,
        "utilization": null
      }
    }
    """

    let response = try JSONDecoder().decode(ClaudeDesktopUsageResponse.self, from: Data(payload.utf8))

    #expect(response.windows.count == 2)
    #expect(response.windows[0].detail == "Current session")
    #expect(Int(response.windows[0].usedPercent.rounded()) == 100)
    #expect(response.windows[0].resetsAt != nil)
    #expect(response.windows[1].detail == "Current week")
    #expect(Int(response.windows[1].usedPercent.rounded()) == 22)
    #expect(response.extraUsage?.isEnabled == false)
}

@Test
func compactValueSupportsFiveHourOnlyMode() {
    let service = ServiceSnapshot(
        service: .claude,
        displayName: "Claude Code",
        accountDescription: nil,
        state: .ready,
        windows: [
            UsageWindow(key: "claude_five_hour", title: "5h", detail: "Current session", usedPercent: 98, resetsAt: nil),
            UsageWindow(key: "claude_seven_day", title: "7d", detail: "Current week", usedPercent: 22, resetsAt: nil),
        ],
        notices: [],
        sourceDescription: "Claude desktop web session",
        capturedAt: nil
    )

    #expect(AppModel.compactValue(for: service, mode: .fiveHourOnly) == "98%")
}

@Test
func cursorAuthReaderLoadsSessionFromLocalCursorInstall() {
    // Verifies JWT + sqlite read on machines where Cursor is installed; no-op elsewhere.
    let dbURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    guard FileManager.default.fileExists(atPath: dbURL.path) else {
        return
    }

    let session = CursorAuthReader.loadSession()
    #expect(session != nil)
}

@Test
func cursorUsageJSONParserMapsDashboardUsageResponse() throws {
    let payload = """
    {
      "gpt-4": {
        "numRequests": 10,
        "numTokens": 1000,
        "maxRequestUsage": 50
      },
      "gpt-4-32k": {
        "numRequests": 3,
        "numTokens": 500,
        "maxRequestUsage": 20
      },
      "startOfMonth": "2026-04-01T12:00:00.000Z"
    }
    """

    let parsed = CursorUsageJSONParser.usageWindows(from: Data(payload.utf8))

    #expect(parsed.windows.count == 2)
    #expect(parsed.windows[0].title == "Included")
    #expect(parsed.windows[0].detail == "gpt-4")
    #expect(Int(parsed.windows[0].usedPercent.rounded()) == 20)
    #expect(parsed.windows[1].title == "On-demand")
    #expect(parsed.windows[1].detail == "gpt-4-32k")
    #expect(Int(parsed.windows[1].usedPercent.rounded()) == 15)
    #expect(parsed.cycleStart != nil)
}

@Test
func compactValueCursorUsesIncludedAndOnDemandMeters() {
    let service = ServiceSnapshot(
        service: .cursor,
        displayName: "Cursor",
        accountDescription: nil,
        state: .ready,
        windows: [
            UsageWindow(key: "cursor_included", title: "Included", detail: "gpt-4", usedPercent: 40, resetsAt: nil),
            UsageWindow(key: "cursor_ondemand", title: "On-demand", detail: "gpt-4-32k", usedPercent: 10, resetsAt: nil),
        ],
        notices: [],
        sourceDescription: "Cursor dashboard usage API",
        capturedAt: nil
    )

    #expect(AppModel.compactValue(for: service, mode: .fiveHourOnly) == "40%")
    #expect(AppModel.compactValue(for: service, mode: .fiveHourAndWeekly) == "40%/10%")
}

@Test
func compactValueCursorPrefersPlanOverIncluded() {
    let service = ServiceSnapshot(
        service: .cursor,
        displayName: "Cursor",
        accountDescription: nil,
        state: .ready,
        windows: [
            UsageWindow(key: "cursor_plan_total", title: "Plan", detail: "Auto 4% · API 100%", usedPercent: 27, resetsAt: nil),
            UsageWindow(key: "cursor_on_demand_spend", title: "On-demand", detail: "$7.91 / $50.00", usedPercent: 16, resetsAt: nil),
            UsageWindow(key: "cursor_included", title: "Included", detail: "gpt-4", usedPercent: 5, resetsAt: nil),
        ],
        notices: [],
        sourceDescription: "summary",
        capturedAt: nil
    )

    #expect(AppModel.compactValue(for: service, mode: .fiveHourOnly) == "27%")
    #expect(AppModel.compactValue(for: service, mode: .fiveHourAndWeekly) == "27%/16%")
}

@Test
func cursorUsageSummaryParserMapsDashboardShape() throws {
    let payload = """
    {
      "billingCycleStart": "2026-03-22T12:05:41.000Z",
      "billingCycleEnd": "2026-04-22T12:05:41.000Z",
      "membershipType": "pro",
      "limitType": "user",
      "isUnlimited": false,
      "autoModelSelectedDisplayMessage": "You've used 27% of your included total usage",
      "namedModelSelectedDisplayMessage": "You've used 100% of your included API usage",
      "individualUsage": {
        "plan": {
          "enabled": true,
          "used": 2000,
          "limit": 2000,
          "remaining": 0,
          "breakdown": { "included": 2000, "bonus": 3361, "total": 5361 },
          "autoPercentUsed": 4.44,
          "apiPercentUsed": 100,
          "totalPercentUsed": 27.49
        },
        "onDemand": {
          "enabled": true,
          "used": 791,
          "limit": 5000,
          "remaining": 4209
        }
      },
      "teamUsage": {}
    }
    """

    let parsed = try #require(CursorUsageSummaryParser.parse(data: Data(payload.utf8)))
    #expect(parsed.windows.count == 2)
    #expect(parsed.windows[0].title == "Plan")
    #expect(Int(parsed.windows[0].usedPercent.rounded()) == 27)
    #expect(parsed.windows[0].detail == "Auto 4% · API 100%")
    #expect(parsed.windows[1].title == "On-demand")
    #expect(Int(parsed.windows[1].usedPercent.rounded()) == 16)
    #expect(parsed.windows[1].detail?.contains("7.91") == true)
    #expect(parsed.windows[1].detail?.contains("50.00") == true)
}

@Test
func compactValueSupportsFiveHourAndWeeklyMode() {
    let service = ServiceSnapshot(
        service: .codex,
        displayName: "Codex",
        accountDescription: nil,
        state: .ready,
        windows: [
            UsageWindow(key: "codex_primary", title: "5h", detail: "Rolling limit", usedPercent: 17, resetsAt: nil),
            UsageWindow(key: "codex_secondary", title: "7d", detail: "Longer rolling limit", usedPercent: 5, resetsAt: nil),
        ],
        notices: [],
        sourceDescription: "Latest token_count event",
        capturedAt: nil
    )

    #expect(AppModel.compactValue(for: service, mode: .fiveHourAndWeekly) == "17%/5%")
}

@Test
func cliCommandRecognizesBackgroundLaunch() {
    let command = CLICommand(arguments: ["AgentStatsBar", "--background"])

    guard case .launchApp(let background) = command.mode else {
        Issue.record("Expected launchApp mode.")
        return
    }

    #expect(background == true)
}

@Test
func launchTargetUsesAppBundleArguments() {
    let target = LaunchTarget.appBundle(URL(fileURLWithPath: "/Applications/Agent Stats.app"))

    #expect(
        target.programArguments == [
            "/usr/bin/open",
            "-g",
            "-j",
            "/Applications/Agent Stats.app",
            "--args",
            "--background",
        ]
    )
}

@Test
func launchTargetUsesExecutableArguments() {
    let target = LaunchTarget.executable(URL(fileURLWithPath: "/tmp/AgentStatsBar"))

    #expect(target.programArguments == ["/tmp/AgentStatsBar", "--background"])
    #expect(target.workingDirectory == "/tmp")
}
