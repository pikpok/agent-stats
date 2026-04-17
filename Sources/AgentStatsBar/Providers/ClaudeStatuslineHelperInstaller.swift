import Foundation

enum ClaudeHelperInstallStatus: Sendable {
    case installed
    case notInstalled
    case notConfigured
    case customStatusLine

    var canAttemptInstall: Bool {
        switch self {
        case .installed, .customStatusLine:
            return false
        case .notInstalled, .notConfigured:
            return true
        }
    }
}

struct ClaudeHelperInstallResult: Sendable {
    let status: ClaudeHelperInstallStatus
    let userMessage: String
}

struct ClaudeStatuslineHelperInstaller: Sendable {
    private let helperURL = Self.helperScriptURL()
    private let settingsURL = Self.settingsURL()

    func status() -> ClaudeHelperInstallStatus {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: helperURL.path) else {
            return .notInstalled
        }

        guard
            let settingsURL,
            fileManager.fileExists(atPath: settingsURL.path),
            let data = try? Data(contentsOf: settingsURL),
            let object = try? JSONSerialization.jsonObject(with: data),
            let json = object as? [String: Any]
        else {
            return .notConfigured
        }

        guard let statusLine = json["statusLine"] as? [String: Any] else {
            return .notConfigured
        }

        let configuredCommand = statusLine["command"] as? String
        return configuredCommand == helperURL.path ? .installed : .customStatusLine
    }

    func install() -> ClaudeHelperInstallResult {
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(
                at: helperURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            try helperScriptContents().write(to: helperURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
        } catch {
            return ClaudeHelperInstallResult(
                status: .notInstalled,
                userMessage: "Failed to write the Claude helper: \(error.localizedDescription)"
            )
        }

        guard let settingsURL else {
            return ClaudeHelperInstallResult(
                status: .notConfigured,
                userMessage: "Claude helper written to \(helperURL.path). Create ~/.claude/settings.json and point statusLine.command at that file."
            )
        }

        var json: [String: Any] = [:]

        if fileManager.fileExists(atPath: settingsURL.path) {
            guard
                let data = try? Data(contentsOf: settingsURL),
                let object = try? JSONSerialization.jsonObject(with: data),
                let existingJSON = object as? [String: Any]
            else {
                return ClaudeHelperInstallResult(
                    status: .notConfigured,
                    userMessage: "Claude helper written to \(helperURL.path), but \(settingsURL.path) is not valid JSON."
                )
            }

            json = existingJSON
        }

        if let existingStatusLine = json["statusLine"] as? [String: Any] {
            let existingCommand = existingStatusLine["command"] as? String
            if existingCommand == helperURL.path {
                return ClaudeHelperInstallResult(
                    status: .installed,
                    userMessage: "Claude helper is already installed."
                )
            }

            return ClaudeHelperInstallResult(
                status: .customStatusLine,
                userMessage: "Claude helper written to \(helperURL.path), but your existing statusLine.command is custom. Wire the helper in manually if you want Claude usage in the app."
            )
        }

        json["statusLine"] = [
            "type": "command",
            "command": helperURL.path,
        ]

        do {
            let output = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try fileManager.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try output.write(to: settingsURL, options: .atomic)
        } catch {
            return ClaudeHelperInstallResult(
                status: .notConfigured,
                userMessage: "Claude helper written to \(helperURL.path), but failed to update \(settingsURL.path): \(error.localizedDescription)"
            )
        }

        return ClaudeHelperInstallResult(
            status: .installed,
            userMessage: "Claude helper installed. Send one Claude Code message to populate the first usage snapshot."
        )
    }

    static func helperScriptURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/agent-stats/claude_statusline.py")
    }

    static func cacheURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/agent-stats/usage.json")
    }

    static func settingsURL() -> URL? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")

        if FileManager.default.fileExists(atPath: path.path) {
            return path.resolvingSymlinksInPath()
        }

        return path
    }

    private func helperScriptContents() -> String {
        """
        #!/usr/bin/env python3
        import json
        import os
        import pathlib
        import sys
        import time

        cache_path = pathlib.Path(os.path.expanduser("~/.claude/agent-stats/usage.json"))
        cache_path.parent.mkdir(parents=True, exist_ok=True)

        raw = sys.stdin.read()

        try:
            payload = json.loads(raw)
        except Exception:
            print("")
            raise SystemExit(0)

        cache = {
            "captured_at": int(time.time()),
            "rate_limits": payload.get("rate_limits"),
            "workspace": {
                "current_dir": (payload.get("workspace") or {}).get("current_dir")
            },
        }

        temp_path = cache_path.with_suffix(".tmp")
        temp_path.write_text(json.dumps(cache, separators=(",", ":")), encoding="utf-8")
        temp_path.replace(cache_path)

        rate_limits = payload.get("rate_limits") or {}
        pieces = []

        for label, key in (("5h", "five_hour"), ("7d", "seven_day"), ("7dS", "seven_day_sonnet")):
            section = rate_limits.get(key) or {}
            used = section.get("used_percentage")
            if isinstance(used, (int, float)):
                pieces.append(f"{label}:{round(float(used))}%")

        print(" ".join(pieces))
        """
    }
}
