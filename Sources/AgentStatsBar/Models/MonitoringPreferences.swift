import Foundation

struct MonitoringPreferences {
    // The bundled app and the standalone snapshot command have different standard defaults domains.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: "com.pikpok.AgentStatsBar.monitoring")!) {
        self.defaults = defaults
    }

    var enabledServices: Set<ServiceKind> {
        Set(ServiceKind.allCases.filter { defaults.object(forKey: $0.rawValue) as? Bool ?? true })
    }

    func setEnabled(_ enabled: Bool, for service: ServiceKind) {
        defaults.set(enabled, forKey: service.rawValue)
    }
}
