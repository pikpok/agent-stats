import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let hostingController: NSHostingController<MenuBarView>
    private let statusContentView = MenuBarStatusContentView()
    private var popover: NSPopover?
    private weak var activeButton: NSStatusBarButton?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var statusItemRefreshScheduled = false
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel, openDashboard: @escaping () -> Void) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.hostingController = NSHostingController(
            rootView: MenuBarView(model: model, openDashboard: openDashboard)
        )
        super.init()

        configureStatusItemButton()
        bindModel()
        updateStatusItem()
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = button(for: sender) else {
            return
        }

        if let popover, popover.isShown {
            if activeButton === button {
                closePopover(sender)
            } else {
                closePopover(nil)
                showPopover(from: button)
            }
            return
        }

        showPopover(from: button)
    }

    private func showPopover(from button: NSStatusBarButton) {
        closePopover(nil)

        let popover = makePopover()
        self.popover = popover
        self.activeButton = button

        button.highlight(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        installOutsideClickMonitors()
    }

    private func closePopover(_ sender: Any?) {
        guard let popover else {
            clearPopoverState()
            return
        }

        if popover.isShown {
            popover.close()
        } else {
            clearPopoverState(for: popover)
        }
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = hostingController
        popover.contentSize = MenuBarView.preferredPopoverSize
        return popover
    }

    private func configureStatusItemButton() {
        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.title = ""
        button.image = nil

        statusContentView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(statusContentView)

        NSLayoutConstraint.activate([
            statusContentView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            statusContentView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            statusContentView.topAnchor.constraint(equalTo: button.topAnchor),
            statusContentView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
    }

    private func bindModel() {
        model.$snapshot
            .sink { [weak self] _ in
                self?.scheduleStatusItemRefresh()
            }
            .store(in: &cancellables)

        model.$menuBarDisplayMode
            .sink { [weak self] _ in
                self?.scheduleStatusItemRefresh()
            }
            .store(in: &cancellables)
    }

    private func scheduleStatusItemRefresh() {
        updateStatusItem()

        guard !statusItemRefreshScheduled else {
            return
        }

        statusItemRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.statusItemRefreshScheduled = false
            self.updateStatusItem()
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else {
            statusItemRefreshScheduled = false
            return
        }

        button.image = nil
        button.title = ""
        button.attributedTitle = NSAttributedString()
        button.toolTip = model.menuBarTitle
        button.setAccessibilityTitle(model.menuBarTitle)

        statusContentView.update(
            items: model.menuBarItems,
            warningImage: model.shouldShowMenuBarSymbol ? makeWarningImage(pointSize: 10) : nil
        )

        statusItem.length = measuredStatusItemLength()
        button.invalidateIntrinsicContentSize()
        button.needsLayout = true
        button.needsDisplay = true
        button.superview?.needsLayout = true
        button.superview?.needsDisplay = true
        button.window?.contentView?.needsLayout = true
        button.window?.contentView?.needsDisplay = true
        button.window?.displayIfNeeded()
    }

    private func makeWarningImage(pointSize: CGFloat) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard let image = NSImage(systemSymbolName: model.menuBarSymbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else {
            return nil
        }

        image.isTemplate = true
        return image
    }

    private func measuredStatusItemLength() -> CGFloat {
        ceil(statusContentView.preferredWidth)
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()

        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else {
                return event
            }

            if self.shouldClosePopover(for: event) {
                self.closePopover(nil)
            }

            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            Task { @MainActor in
                guard let self else {
                    return
                }

                if self.shouldClosePopover(for: event) {
                    self.closePopover(nil)
                }
            }
        }
    }

    private func removeOutsideClickMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }

        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private func shouldClosePopover(for event: NSEvent) -> Bool {
        guard let popover, popover.isShown else {
            return false
        }

        let screenPoint = screenLocation(for: event)
        return !isPointInsideActiveButton(screenPoint) && !isPointInsidePopover(screenPoint)
    }

    private func screenLocation(for event: NSEvent) -> CGPoint {
        guard let window = event.window else {
            return NSEvent.mouseLocation
        }

        return window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
    }

    private func isPointInsideActiveButton(_ point: CGPoint) -> Bool {
        guard
            let activeButton,
            let buttonWindow = activeButton.window
        else {
            return false
        }

        let buttonRect = activeButton.convert(activeButton.bounds, to: nil)
        return buttonWindow.convertToScreen(buttonRect).contains(point)
    }

    private func isPointInsidePopover(_ point: CGPoint) -> Bool {
        popover?.contentViewController?.view.window?.frame.contains(point) == true
    }

    private func button(for sender: Any?) -> NSStatusBarButton? {
        if let button = sender as? NSStatusBarButton {
            return button
        }

        return statusItem.button
    }

    private func clearPopoverState(for closingPopover: NSPopover? = nil) {
        if let closingPopover, closingPopover !== popover {
            return
        }

        activeButton?.highlight(false)
        activeButton = nil
        removeOutsideClickMonitors()
        popover = nil
    }

    func popoverDidClose(_ notification: Notification) {
        clearPopoverState(for: notification.object as? NSPopover)
    }
}
