import SwiftUI

struct ServiceSectionView: View {
    let service: ServiceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                ServiceGlyphView(service: service.service, size: 14)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text(service.displayName)
                        .font(.subheadline.weight(.semibold))

                    if let accountDescription = service.accountDescription {
                        Text(accountDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                StatusBadgeView(state: service.state)
            }

            if service.windows.isEmpty {
                Text(service.fallbackText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(service.windows) { window in
                        UsageWindowRowView(window: window, tint: service.service.accentColor)
                    }
                }
            }

            if !service.notices.isEmpty || !service.sourceDescription.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(service.notices, id: \.self) { notice in
                        Text(notice)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(service.sourceDescription)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(cardOutline)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        service.service.accentColor.opacity(0.14),
                        Color(nsColor: .controlBackgroundColor).opacity(0.92),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var cardOutline: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.8)
    }
}

struct UsageWindowRowView: View {
    let window: UsageWindow
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 8) {
                Text(window.title)
                    .font(.caption.weight(.semibold))
                    .frame(width: 48, alignment: .leading)

                UsageBarView(usedPercent: window.usedPercent, tint: tint)

                Text(window.percentText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(width: 42, alignment: .trailing)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let detail = window.detail {
                    Text(detail)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if let resetsAt = window.resetsAt {
                    Text("Reset \(resetsAt, style: .relative)")
                        .lineLimit(1)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

struct UsageBarView: View {
    let usedPercent: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let clampedPercent = max(0, min(usedPercent, 100))
            let fillWidth = proxy.size.width * (clampedPercent / 100)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))

                Capsule()
                    .fill(tint.opacity(0.92))
                    .frame(width: max(fillWidth, clampedPercent == 0 ? 0 : 4))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 7)
    }
}

struct StatusBadgeView: View {
    let state: ServiceState

    var body: some View {
        Text(state.label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(state.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(state.color.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(state.color.opacity(0.3), lineWidth: 0.8)
            )
    }
}
