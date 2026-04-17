import Foundation

enum CursorUsageSummaryParser: Sendable {
    static func parse(data: Data) -> (
        windows: [UsageWindow],
        notices: [String],
        billingCycleEnd: Date?
    )? {
        let decoder = JSONDecoder()
        guard let summary = try? decoder.decode(CursorUsageSummaryResponse.self, from: data) else {
            return nil
        }

        guard let plan = summary.individualUsage?.plan, plan.enabled else {
            return nil
        }

        let cycleEnd = parseISO8601(summary.billingCycleEnd)

        var windows: [UsageWindow] = []

        let totalPct = min(100, max(0, plan.totalPercentUsed))
        let autoInt = Int(plan.autoPercentUsed.rounded())
        let apiInt = Int(plan.apiPercentUsed.rounded())

        windows.append(
            UsageWindow(
                key: "cursor_plan_total",
                title: "Plan",
                detail: "Auto \(autoInt)% · API \(apiInt)%",
                usedPercent: totalPct,
                resetsAt: cycleEnd
            )
        )

        let onDemand = summary.individualUsage?.onDemand ?? summary.teamUsage?.onDemand
        if let od = onDemand, od.enabled, od.limit > 0 {
            let spendPct = min(100, Double(od.used) / Double(od.limit) * 100)
            let dollars = usdPair(usedCents: od.used, limitCents: od.limit)
            windows.append(
                UsageWindow(
                    key: "cursor_on_demand_spend",
                    title: "On-demand",
                    detail: dollars,
                    usedPercent: spendPct,
                    resetsAt: cycleEnd
                )
            )
        }

        var notices: [String] = []
        if let msg = summary.autoModelSelectedDisplayMessage, !msg.isEmpty {
            notices.append(msg)
        }
        if let msg = summary.namedModelSelectedDisplayMessage, !msg.isEmpty {
            notices.append(msg)
        }

        return (windows, notices, cycleEnd)
    }

    private static func parseISO8601(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = fractional.date(from: value) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    private static func usdPair(usedCents: Int, limitCents: Int) -> String {
        let used = Double(usedCents) / 100
        let limit = Double(limitCents) / 100
        return String(format: "$%.2f / $%.2f", used, limit)
    }
}

private struct CursorUsageSummaryResponse: Decodable, Sendable {
    let billingCycleStart: String?
    let billingCycleEnd: String?
    let membershipType: String?
    let autoModelSelectedDisplayMessage: String?
    let namedModelSelectedDisplayMessage: String?
    let individualUsage: IndividualUsage?
    let teamUsage: TeamUsage?

    struct IndividualUsage: Decodable, Sendable {
        let plan: PlanBucket?
        let onDemand: OnDemandBucket?
    }

    struct TeamUsage: Decodable, Sendable {
        let onDemand: OnDemandBucket?
    }

    struct PlanBucket: Decodable, Sendable {
        let enabled: Bool
        let autoPercentUsed: Double
        let apiPercentUsed: Double
        let totalPercentUsed: Double
    }

    struct OnDemandBucket: Decodable, Sendable {
        let enabled: Bool
        let used: Int
        let limit: Int
        let remaining: Int
    }
}
