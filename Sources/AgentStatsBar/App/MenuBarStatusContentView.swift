import AppKit

@MainActor
final class MenuBarStatusContentView: NSView {
    private enum Metrics {
        static let iconSize: CGFloat = 8
        static let warningSize: CGFloat = 9
        static let horizontalPadding: CGFloat = 3
        static let iconSpacing: CGFloat = 2
        static let columnSpacing: CGFloat = 2
        static let rowSpacing: CGFloat = 0
        static let fontSize: CGFloat = 8
    }

    private let rootStackView = NSStackView()
    private let warningImageView = NSImageView()
    private let rowsStackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()

        let fittingSize = rootStackView.fittingSize
        let origin = CGPoint(
            x: Metrics.horizontalPadding,
            y: round((bounds.height - fittingSize.height) / 2)
        )

        rootStackView.frame = CGRect(origin: origin, size: fittingSize)
    }

    var preferredWidth: CGFloat {
        let width = rootStackView.fittingSize.width + (Metrics.horizontalPadding * 2)
        return max(width, 36)
    }

    func update(items: [MenuBarServiceItem], warningImage: NSImage?) {
        warningImageView.image = warningImage
        warningImageView.isHidden = warningImage == nil

        rowsStackView.arrangedSubviews.forEach { view in
            rowsStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if items.isEmpty {
            rowsStackView.addArrangedSubview(makeFallbackLabel())
        } else {
            items.forEach { item in
                rowsStackView.addArrangedSubview(makeRow(for: item))
            }
        }

        needsLayout = true
        layoutSubtreeIfNeeded()
        invalidateIntrinsicContentSize()
    }

    private func setupView() {
        wantsLayer = false

        warningImageView.imageScaling = .scaleProportionallyDown
        warningImageView.isHidden = true
        warningImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            warningImageView.widthAnchor.constraint(equalToConstant: Metrics.warningSize),
            warningImageView.heightAnchor.constraint(equalToConstant: Metrics.warningSize),
        ])

        rowsStackView.orientation = .vertical
        rowsStackView.alignment = .leading
        rowsStackView.spacing = Metrics.rowSpacing
        rowsStackView.translatesAutoresizingMaskIntoConstraints = false

        rootStackView.orientation = .horizontal
        rootStackView.alignment = .centerY
        rootStackView.spacing = Metrics.columnSpacing
        rootStackView.detachesHiddenViews = true
        rootStackView.translatesAutoresizingMaskIntoConstraints = true

        rootStackView.addArrangedSubview(warningImageView)
        rootStackView.addArrangedSubview(rowsStackView)
        addSubview(rootStackView)
    }

    private func makeRow(for item: MenuBarServiceItem) -> NSView {
        let iconView = NSImageView(image: makeServiceImage(for: item.service))
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Metrics.iconSize),
        ])

        let label = NSTextField(labelWithString: item.valueText)
        label.font = NSFont.monospacedDigitSystemFont(ofSize: Metrics.fontSize, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byClipping

        let stackView = NSStackView(views: [iconView, label])
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = Metrics.iconSpacing

        return stackView
    }

    private func makeFallbackLabel() -> NSView {
        let label = NSTextField(labelWithString: "Agent Stats")
        label.font = NSFont.systemFont(ofSize: Metrics.fontSize, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    private func makeServiceImage(for service: ServiceKind) -> NSImage {
        ServiceIconRenderer.image(for: service, pointSize: Metrics.iconSize)
    }
}
