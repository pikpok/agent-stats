import Foundation

enum CursorUsageJSONParser: Sendable {
    private static let includedModelPriority = [
        "gpt-4",
        "gpt-4o",
        "claude-3-5-sonnet",
        "claude-3.5-sonnet",
        "claude-4-sonnet",
    ]

    private static let onDemandKeys: Set<String> = [
        "gpt-4-32k",
        "gpt-4-turbo",
        "o1",
        "o1-mini",
        "o3",
    ]

    static func usageWindows(from data: Data) -> (windows: [UsageWindow], cycleStart: Date?) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], nil)
        }

        let cycleStart = parseStartOfMonth(from: root)

        var modelEntries: [(key: String, payload: [String: Any])] = []
        for (key, value) in root {
            if key == "startOfMonth" {
                continue
            }

            guard let payload = value as? [String: Any] else {
                continue
            }

            modelEntries.append((key: key, payload: payload))
        }

        guard !modelEntries.isEmpty else {
            return ([], cycleStart)
        }

        let resetsAt = billingCycleEnd(from: cycleStart)

        let primaryKey = pickPrimaryModelKey(from: modelEntries.map(\.key))
        let primaryPayload = primaryKey.flatMap { key in modelEntries.first(where: { $0.key == key })?.payload }
        let secondaryEntry = modelEntries.first(where: { Self.onDemandKeys.contains($0.key) })

        var windows: [UsageWindow] = []

        if
            let primaryKey,
            let primaryPayload,
            let window = window(from: primaryPayload, keyPrefix: "cursor_included", title: "Included", detailLabel: primaryKey, resetsAt: resetsAt)
        {
            windows.append(window)
        }

        if
            let secondaryEntry,
            secondaryEntry.key != primaryKey,
            let window = window(
                from: secondaryEntry.payload,
                keyPrefix: "cursor_ondemand",
                title: "On-demand",
                detailLabel: secondaryEntry.key,
                resetsAt: resetsAt
            )
        {
            windows.append(window)
        }

        if windows.isEmpty {
            for entry in modelEntries.sorted(by: { $0.key < $1.key }) {
                if let window = window(
                    from: entry.payload,
                    keyPrefix: "cursor_\(entry.key)",
                    title: "Included",
                    detailLabel: entry.key,
                    resetsAt: resetsAt
                ) {
                    windows.append(window)
                    break
                }
            }
        }

        return (windows, cycleStart)
    }

    private static func parseStartOfMonth(from root: [String: Any]) -> Date? {
        if let string = root["startOfMonth"] as? String {
            return parseISO8601(string)
        }

        if let number = root["startOfMonth"] as? TimeInterval {
            return Date(timeIntervalSince1970: number)
        }

        return nil
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = fractional.date(from: value) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    private static func billingCycleEnd(from cycleStart: Date?) -> Date? {
        guard let cycleStart else {
            return nil
        }

        return Calendar.current.date(byAdding: .month, value: 1, to: cycleStart)
    }

    private static func pickPrimaryModelKey(from keys: [String]) -> String? {
        for candidate in Self.includedModelPriority {
            if keys.contains(candidate) {
                return candidate
            }
        }

        let nonOnDemand = keys.filter { !Self.onDemandKeys.contains($0) }.sorted()
        if let first = nonOnDemand.first {
            return first
        }

        return keys.sorted().first
    }

    private static func window(
        from payload: [String: Any],
        keyPrefix: String,
        title: String,
        detailLabel: String,
        resetsAt: Date?
    ) -> UsageWindow? {
        let current = intValue(payload["numRequests"]) ?? intValue(payload["numRequestsTotal"])
        let limit = intValue(payload["maxRequestUsage"]) ?? intValue(payload["maxTokenUsage"])

        guard let current, current >= 0 else {
            return nil
        }

        guard let limit, limit > 0 else {
            return UsageWindow(
                key: keyPrefix,
                title: title,
                detail: detailLabel,
                usedPercent: 0,
                resetsAt: resetsAt
            )
        }

        let usedPercent = min(100, Double(current) / Double(limit) * 100)

        return UsageWindow(
            key: keyPrefix,
            title: title,
            detail: detailLabel,
            usedPercent: usedPercent,
            resetsAt: resetsAt
        )
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as Int:
            return number
        case let number as Double:
            return Int(number)
        case let number as NSNumber:
            return number.intValue
        default:
            return nil
        }
    }
}
