import Foundation
import SwiftUI

enum ServiceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case claude
    case cursor

    var id: String { rawValue }

    var compactLabel: String {
        switch self {
        case .codex:
            return "Co"
        case .claude:
            return "Cl"
        case .cursor:
            return "Cu"
        }
    }

    var sortOrder: Int {
        switch self {
        case .codex:
            return 0
        case .claude:
            return 1
        case .cursor:
            return 2
        }
    }

    var accentColor: Color {
        switch self {
        case .codex:
            return Color(red: 0.14, green: 0.58, blue: 0.48)
        case .claude:
            return Color(red: 0.78, green: 0.43, blue: 0.20)
        case .cursor:
            return Color(red: 0.26, green: 0.52, blue: 0.96)
        }
    }
}

enum ServiceState: String, Codable, Sendable {
    case ready
    case stale
    case needsSetup
    case loggedOut
    case error

    var label: String {
        switch self {
        case .ready:
            return "Ready"
        case .stale:
            return "Stale"
        case .needsSetup:
            return "Setup"
        case .loggedOut:
            return "Logged Out"
        case .error:
            return "Error"
        }
    }

    var color: Color {
        switch self {
        case .ready:
            return .green
        case .stale:
            return .orange
        case .needsSetup:
            return .yellow
        case .loggedOut, .error:
            return .red
        }
    }
}

struct ServiceSnapshot: Identifiable, Codable, Sendable {
    let service: ServiceKind
    let displayName: String
    let accountDescription: String?
    let state: ServiceState
    let windows: [UsageWindow]
    let notices: [String]
    let sourceDescription: String
    let capturedAt: Date?

    var id: ServiceKind { service }

    var fallbackText: String {
        switch state {
        case .loggedOut:
            return "No active credentials found."
        case .needsSetup:
            return "Usage data is available after setup."
        case .stale:
            return "No fresh usage snapshot is available right now."
        case .error:
            return "The latest usage data could not be read."
        case .ready:
            return "No usage windows available."
        }
    }
}

struct UsageWindow: Identifiable, Codable, Sendable {
    let key: String
    let title: String
    let detail: String?
    let usedPercent: Double
    let resetsAt: Date?

    var id: String { key }

    var percentText: String {
        "\(Int(usedPercent.rounded()))%"
    }
}
