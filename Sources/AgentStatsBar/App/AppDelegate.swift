import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusItemController: StatusItemController?
    private var dashboardWindowController: DashboardWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let model = AppModel()
        self.model = model
        statusItemController = StatusItemController(model: model) { [weak self] in
            self?.showDashboard(nil)
        }

        if AppRuntime.showsDashboardOnLaunch {
            showDashboard(nil)
        }
    }

    @objc
    func showDashboard(_ sender: Any?) {
        if dashboardWindowController == nil, let model {
            dashboardWindowController = DashboardWindowController(model: model)
        }
        dashboardWindowController?.show()
    }
}
