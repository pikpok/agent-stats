import SwiftUI

struct DashboardView: View {
    static let defaultWindowSize = CGSize(width: 620, height: 700)

    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    overviewCards
                    serviceStack
                    settingsPanel
                }
                .padding(20)
            }
        }
        .frame(
            minWidth: Self.defaultWindowSize.width,
            minHeight: Self.defaultWindowSize.height
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Agent Stats")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Button("Refresh Now") {
                model.refreshNow()
            }
            .controlSize(.large)

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 10)
            }
        }
    }

    private var overviewCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(model.snapshot.services) { service in
                OverviewCardView(service: service, mode: model.menuBarDisplayMode)
            }
        }
    }

    private var serviceStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Usage Details")
                .font(.headline)

            ForEach(model.snapshot.services) { service in
                ServiceSectionView(service: service)
            }
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Startup & Setup")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                    .toggleStyle(.switch)

                Text(model.launchAtLoginCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(model.launchAtLoginTargetDescription)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)

                Divider()

                HStack(spacing: 10) {
                    Picker("Menu Bar Display", selection: $model.menuBarDisplayMode) {
                        ForEach(MenuBarDisplayMode.allCases) { mode in
                            Text(mode.pickerLabel).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if model.helperStatus.canAttemptInstall {
                        Button("Install Claude Helper") {
                            model.installClaudeHelper()
                        }
                    }
                }

                if let transientMessage = model.transientMessage {
                    Text(transientMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.8)
            )
        }
    }

    private var headerSubtitle: String {
        if let fetchedAt = model.snapshot.fetchedAt {
            return "Updated \(fetchedAt.formatted(date: .abbreviated, time: .shortened)). The menu bar stays live in the background."
        }

        return "Waiting for the first usage snapshot."
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLoginEnabled },
            set: { model.setLaunchAtLogin($0) }
        )
    }
}

private struct OverviewCardView: View {
    let service: ServiceSnapshot
    let mode: MenuBarDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                ServiceGlyphView(service: service.service, size: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(service.displayName)
                        .font(.headline)

                    if let accountDescription = service.accountDescription {
                        Text(accountDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                StatusBadgeView(state: service.state)
            }

            Text(AppModel.compactValue(for: service, mode: mode) ?? service.fallbackText)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(service.service.accentColor)
                .fixedSize(horizontal: false, vertical: true)

            Text(resetSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            service.service.accentColor.opacity(0.18),
                            Color(nsColor: .controlBackgroundColor).opacity(0.88),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.8)
        )
    }

    private var resetSummary: String {
        let summaries = service.windows.compactMap { window -> String? in
            guard let resetsAt = window.resetsAt else {
                return nil
            }

            return "\(window.title) resets \(resetsAt.formatted(date: .omitted, time: .shortened))"
        }

        return summaries.isEmpty ? service.sourceDescription : summaries.joined(separator: "  ")
    }
}
