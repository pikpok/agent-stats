import AppKit

@MainActor
enum MenuBarStatusRenderer {
    private enum Metrics {
        static let iconSize: CGFloat = 8
        static let warningSize: CGFloat = 9
        static let horizontalPadding: CGFloat = 3
        static let iconSpacing: CGFloat = 2
        static let columnSpacing: CGFloat = 2
        static let rowSpacing: CGFloat = 1
        static let fontSize: CGFloat = 8
    }

    static func render(items: [MenuBarServiceItem], warningImage: NSImage?) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: Metrics.fontSize, weight: .semibold)
        let fallbackFont = NSFont.systemFont(ofSize: Metrics.fontSize, weight: .semibold)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]

        if items.isEmpty {
            let fallbackText = "Agent Stats"
            let fallbackAttrs: [NSAttributedString.Key: Any] = [
                .font: fallbackFont,
                .foregroundColor: NSColor.labelColor,
            ]
            let textSize = (fallbackText as NSString).size(withAttributes: fallbackAttrs)
            let totalWidth = Metrics.horizontalPadding * 2 + textSize.width
            let totalHeight = textSize.height
            let imageSize = NSSize(width: ceil(totalWidth), height: ceil(totalHeight))
            let image = NSImage(size: imageSize)
            image.lockFocus()
            (fallbackText as NSString).draw(
                at: NSPoint(x: Metrics.horizontalPadding, y: 0),
                withAttributes: fallbackAttrs
            )
            image.unlockFocus()
            image.isTemplate = true
            return image
        }

        struct RowLayout {
            let icon: NSImage
            let text: String
            let textSize: NSSize
            let width: CGFloat
            let height: CGFloat
        }

        var rows: [RowLayout] = []
        for item in items {
            let icon = ServiceIconRenderer.image(for: item.service, pointSize: Metrics.iconSize)
            let textSize = (item.valueText as NSString).size(withAttributes: textAttributes)
            let rowWidth = Metrics.iconSize + Metrics.iconSpacing + textSize.width
            let rowHeight = max(Metrics.iconSize, textSize.height)
            rows.append(RowLayout(icon: icon, text: item.valueText, textSize: textSize, width: rowWidth, height: rowHeight))
        }

        let contentWidth = rows.map(\.width).max() ?? 0
        let contentHeight = rows.map(\.height).reduce(0, +) + Metrics.rowSpacing * CGFloat(max(rows.count - 1, 0))

        var totalWidth = Metrics.horizontalPadding * 2 + contentWidth
        if let warningImage {
            totalWidth += warningImage.size.width + Metrics.columnSpacing
        }

        let imageSize = NSSize(width: ceil(totalWidth), height: ceil(contentHeight))
        let image = NSImage(size: imageSize)
        image.lockFocus()

        var xOffset = Metrics.horizontalPadding

        if let warningImage {
            let warningY = (contentHeight - warningImage.size.height) / 2
            warningImage.draw(
                in: NSRect(origin: NSPoint(x: xOffset, y: warningY), size: warningImage.size),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            xOffset += warningImage.size.width + Metrics.columnSpacing
        }

        var yOffset = contentHeight
        for row in rows {
            yOffset -= row.height
            let iconY = yOffset + (row.height - Metrics.iconSize) / 2
            row.icon.draw(
                in: NSRect(x: xOffset, y: iconY, width: Metrics.iconSize, height: Metrics.iconSize),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )

            let textY = yOffset + (row.height - row.textSize.height) / 2
            (row.text as NSString).draw(
                at: NSPoint(x: xOffset + Metrics.iconSize + Metrics.iconSpacing, y: textY),
                withAttributes: textAttributes
            )

            yOffset -= Metrics.rowSpacing
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    static func preferredWidth(items: [MenuBarServiceItem], warningImage: NSImage?) -> CGFloat {
        let image = render(items: items, warningImage: warningImage)
        return max(image.size.width, 36)
    }
}
