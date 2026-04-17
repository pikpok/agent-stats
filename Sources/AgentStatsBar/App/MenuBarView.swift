import AppKit
import SwiftUI

struct MenuBarView: View {
    static let preferredPopoverSize = NSSize(width: 360, height: 440)

    @ObservedObject var model: AppModel
    let openDashboard: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.snapshot.services) { service in
                        ServiceSectionView(service: service)
                    }
                }

                if let transientMessage = model.transientMessage {
                    Text(transientMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                        )
                }

                Divider()

                controls
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .frame(
            width: Self.preferredPopoverSize.width,
            height: Self.preferredPopoverSize.height
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Agent Stats")
                    .font(.headline.weight(.semibold))

                if let fetchedAt = model.snapshot.fetchedAt {
                    Text("Updated \(fetchedAt, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Waiting for data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launch at Login", isOn: launchAtLoginBinding)
                .toggleStyle(.switch)

            Text(model.launchAtLoginCaption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Menu Bar Display")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Menu Bar Display", selection: $model.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.pickerLabel)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
            }

            HStack(spacing: 10) {
                Button("Show Dashboard") {
                    openDashboard()
                }

                Button("Refresh Now") {
                    model.refreshNow()
                }

                if model.helperStatus.canAttemptInstall {
                    Button("Install Claude Helper") {
                        model.installClaudeHelper()
                    }
                }

                Spacer(minLength: 8)

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLoginEnabled },
            set: { model.setLaunchAtLogin($0) }
        )
    }
}
