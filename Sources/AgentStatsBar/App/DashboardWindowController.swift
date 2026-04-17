import AppKit
import SwiftUI

@MainActor
final class DashboardWindowController: NSWindowController {
    init(model: AppModel) {
        let contentViewController = NSHostingController(rootView: DashboardView(model: model))
        let window = NSWindow(contentViewController: contentViewController)

        window.title = "Agent Stats"
        window.identifier = NSUserInterfaceItemIdentifier("AgentStatsDashboardWindow")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: DashboardView.defaultWindowSize.width, height: DashboardView.defaultWindowSize.height))
        window.minSize = NSSize(width: 560, height: 620)
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else {
            return
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
