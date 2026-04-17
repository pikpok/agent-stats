import Foundation

struct CodexAppServerRateLimitFetcher: Sendable {
    func fetch(accountDescription: String?) async -> ServiceSnapshot? {
        guard let result = await Self.fetchSynchronously() else {
            return nil
        }

        guard let snapshot = ParsedCodexSnapshot(appServerResponse: result.response) else {
            return nil
        }

        var notices: [String] = []
        if let planType = snapshot.planType, !planType.isEmpty {
            notices.append("Plan type: \(planType)")
        }

        return ServiceSnapshot(
            service: .codex,
            displayName: "Codex",
            accountDescription: accountDescription,
            state: .ready,
            windows: snapshot.windows,
            notices: notices,
            sourceDescription: "Codex app-server live rate limits",
            capturedAt: result.capturedAt
        )
    }

    private static func fetchSynchronously() async -> CodexAppServerFetchResult? {
        await Task.detached(priority: .utility) {
            fetchSynchronouslyBlocking()
        }
        .value
    }

    private static func fetchSynchronouslyBlocking() -> CodexAppServerFetchResult? {
        guard let executableURL = locateCodexExecutable() else {
            return nil
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["app-server"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let completion = DispatchGroup()
        completion.enter()
        process.terminationHandler = { _ in
            completion.leave()
        }

        do {
            try process.run()
        } catch {
            completion.leave()
            return nil
        }

        let timeoutWorkItem = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8, execute: timeoutWorkItem)

        var stdoutBuffer = Data()
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stdinHandle = stdinPipe.fileHandleForWriting

        defer {
            timeoutWorkItem.cancel()
            try? stdinHandle.close()
            if process.isRunning {
                process.terminate()
            }
            _ = completion.wait(timeout: .now() + 1)
        }

        guard sendRequest(CodexAppServerRequest.initialize, to: stdinHandle) else {
            return nil
        }

        guard readResponse(withID: 1, from: stdoutHandle, buffer: &stdoutBuffer, as: CodexAppServerInitializeResponse.self) != nil else {
            return nil
        }

        guard sendRequest(CodexAppServerRequest.readRateLimits, to: stdinHandle) else {
            return nil
        }

        guard let response = readRateLimitsResponse(withID: 2, from: stdoutHandle, buffer: &stdoutBuffer) else {
            return nil
        }

        try? stdinHandle.close()
        return CodexAppServerFetchResult(response: response, capturedAt: Date())
    }

    private static func sendRequest(_ request: CodexAppServerRequest, to handle: FileHandle) -> Bool {
        let encoder = JSONEncoder()

        guard let data = try? encoder.encode(request) else {
            return false
        }

        do {
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0A]))
            return true
        } catch {
            return false
        }
    }

    private static func readResponse<Response: Decodable>(
        withID targetID: Int,
        from handle: FileHandle,
        buffer: inout Data,
        as type: Response.Type
    ) -> Response? {
        while let line = readNextLine(from: handle, buffer: &buffer) {
            guard
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let id = object["id"] as? Int,
                id == targetID,
                let result = object["result"],
                JSONSerialization.isValidJSONObject(result),
                let resultData = try? JSONSerialization.data(withJSONObject: result)
            else {
                continue
            }

            return try? JSONDecoder().decode(Response.self, from: resultData)
        }

        return nil
    }

    private static func readRateLimitsResponse(
        withID targetID: Int,
        from handle: FileHandle,
        buffer: inout Data
    ) -> CodexAppServerRateLimitsResponse? {
        while let line = readNextLine(from: handle, buffer: &buffer) {
            guard
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let id = object["id"] as? Int,
                id == targetID
            else {
                continue
            }

            if
                let result = object["result"],
                JSONSerialization.isValidJSONObject(result),
                let resultData = try? JSONSerialization.data(withJSONObject: result),
                let response = try? JSONDecoder().decode(CodexAppServerRateLimitsResponse.self, from: resultData)
            {
                return response
            }

            if
                let error = object["error"] as? [String: Any],
                let message = error["message"] as? String,
                let response = CodexAppServerRateLimitsResponse(recoveringAppServerErrorMessage: message)
            {
                return response
            }
        }

        return nil
    }

    fileprivate static func extractEmbeddedJSONObject(after marker: String, in message: String) -> String? {
        guard
            let markerRange = message.range(of: marker),
            let startIndex = message[markerRange.upperBound...].firstIndex(of: "{")
        else {
            return nil
        }

        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var currentIndex = startIndex

        while currentIndex < message.endIndex {
            let character = message[currentIndex]

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else {
                if character == "\"" {
                    isInsideString = true
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(message[startIndex...currentIndex])
                    }
                }
            }

            currentIndex = message.index(after: currentIndex)
        }

        return nil
    }

    private static func readNextLine(from handle: FileHandle, buffer: inout Data) -> String? {
        while true {
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.prefix(upTo: newlineIndex)
                buffer.removeSubrange(...newlineIndex)
                return String(data: lineData, encoding: .utf8)
            }

            let chunk = handle.availableData
            if chunk.isEmpty {
                guard !buffer.isEmpty else {
                    return nil
                }

                defer {
                    buffer.removeAll(keepingCapacity: true)
                }
                return String(data: buffer, encoding: .utf8)
            }

            buffer.append(chunk)
        }
    }

    private static func locateCodexExecutable() -> URL? {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let environment = ProcessInfo.processInfo.environment

        var candidates: [String] = []
        if let explicitPath = environment["CODEX_BINARY"], !explicitPath.isEmpty {
            candidates.append(explicitPath)
        }

        if let path = environment["PATH"], !path.isEmpty {
            candidates.append(contentsOf: path.split(separator: ":").map { String($0) + "/codex" })
        }

        candidates.append(contentsOf: [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            homeDirectory.appendingPathComponent(".local/bin/codex").path,
        ])

        for candidate in candidates {
            guard fileManager.isExecutableFile(atPath: candidate) else {
                continue
            }

            return URL(fileURLWithPath: candidate)
        }

        return nil
    }
}

private struct CodexAppServerFetchResult: Sendable {
    let response: CodexAppServerRateLimitsResponse
    let capturedAt: Date
}

private enum CodexAppServerRequest: Encodable {
    case initialize
    case readRateLimits

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .initialize:
            try container.encode(1, forKey: .id)
            try container.encode("initialize", forKey: .method)
            try container.encode(CodexAppServerInitializeParams(), forKey: .params)
        case .readRateLimits:
            try container.encode(2, forKey: .id)
            try container.encode("account/rateLimits/read", forKey: .method)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case method
        case params
    }
}

private struct CodexAppServerInitializeParams: Encodable {
    let clientInfo = ClientInfo()
    let capabilities = Capabilities()

    struct ClientInfo: Encodable {
        let name = "AgentStatsBar"
        let version = "0.1"
    }

    struct Capabilities: Encodable {
        let experimentalApi = true
    }
}

private struct CodexAppServerInitializeResponse: Decodable {
    let userAgent: String
}

private struct CodexWhamUsageResponse: Decodable {
    let planType: String?
    let rateLimit: RateLimit?
    let credits: CodexWhamCredits?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
    }

    var asRateLimitsResponse: CodexAppServerRateLimitsResponse? {
        guard let snapshot = asRateLimitSnapshot else {
            return nil
        }

        return CodexAppServerRateLimitsResponse(
            rateLimits: snapshot,
            rateLimitsByLimitId: ["codex": snapshot]
        )
    }

    private var asRateLimitSnapshot: CodexAppServerRateLimitSnapshot? {
        let primaryWindow = rateLimit?.primaryWindow?.asAppServerWindow
        let secondaryWindow = rateLimit?.secondaryWindow?.asAppServerWindow

        guard primaryWindow != nil || secondaryWindow != nil else {
            return nil
        }

        return CodexAppServerRateLimitSnapshot(
            limitId: "codex",
            limitName: nil,
            primary: primaryWindow,
            secondary: secondaryWindow,
            credits: credits?.asAppServerCredits,
            planType: planType
        )
    }

    struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct Window: Decodable {
        let usedPercent: Double
        let limitWindowSeconds: Int?
        let resetAt: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case limitWindowSeconds = "limit_window_seconds"
            case resetAt = "reset_at"
        }

        var asAppServerWindow: CodexAppServerRateLimitWindow {
            CodexAppServerRateLimitWindow(
                usedPercent: Int(usedPercent.rounded()),
                windowDurationMins: limitWindowSeconds.map { $0 / 60 },
                resetsAt: resetAt
            )
        }
    }

    struct CodexWhamCredits: Decodable {
        let hasCredits: Bool?
        let unlimited: Bool?
        let balance: String?

        enum CodingKeys: String, CodingKey {
            case hasCredits = "has_credits"
            case unlimited
            case balance
        }

        var asAppServerCredits: CodexAppServerCreditsSnapshot {
            CodexAppServerCreditsSnapshot(
                hasCredits: hasCredits ?? false,
                unlimited: unlimited ?? false,
                balance: balance
            )
        }
    }
}

struct CodexAppServerRateLimitsResponse: Decodable, Sendable {
    let rateLimits: CodexAppServerRateLimitSnapshot
    let rateLimitsByLimitId: [String: CodexAppServerRateLimitSnapshot]?

    init(rateLimits: CodexAppServerRateLimitSnapshot, rateLimitsByLimitId: [String: CodexAppServerRateLimitSnapshot]?) {
        self.rateLimits = rateLimits
        self.rateLimitsByLimitId = rateLimitsByLimitId
    }

    init?(recoveringAppServerErrorMessage message: String) {
        guard
            message.contains("failed to fetch codex rate limits"),
            message.contains("unknown variant `prolite`") || message.contains("unknown variant \"prolite\""),
            let payload = CodexAppServerRateLimitFetcher.extractEmbeddedJSONObject(after: "body=", in: message),
            let data = payload.data(using: .utf8),
            let usage = try? JSONDecoder().decode(CodexWhamUsageResponse.self, from: data),
            let response = usage.asRateLimitsResponse
        else {
            return nil
        }

        self = response
    }
}

struct CodexAppServerRateLimitSnapshot: Decodable, Sendable {
    let limitId: String?
    let limitName: String?
    let primary: CodexAppServerRateLimitWindow?
    let secondary: CodexAppServerRateLimitWindow?
    let credits: CodexAppServerCreditsSnapshot?
    let planType: String?
}

struct CodexAppServerRateLimitWindow: Decodable, Sendable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?
}

struct CodexAppServerCreditsSnapshot: Decodable, Sendable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}
