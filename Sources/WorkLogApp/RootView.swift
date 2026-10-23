import AppKit
import Combine
import SwiftUI
import WorkLogCore

struct RootView: View {
    let model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 196, ideal: 208, max: 240)
        } detail: {
            Group {
                switch model.selectedSection {
                case .calendar:
                    CalendarWorkspaceView(model: model)
                case .work:
                    WorkWorkspaceView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.pageBackground)
        }
        .tint(AppTheme.accent)
        .frame(minWidth: 1080, minHeight: 680)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            Task { @MainActor in
                NSApplication.shared.terminate(nil)
            }
        }
        .task {
            await model.bootstrap()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.handleActivation() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .workLogGoToday)) { _ in
            Task { await model.goToToday() }
        }
        .alert("提示", isPresented: errorPresented) {
            Button("好", role: .cancel) {
                model.clearError()
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    model.clearError()
                }
            }
        )
    }
}

private struct SidebarView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 18)

            VStack(spacing: 4) {
                ForEach(AppModel.Section.allCases) { section in
                    SidebarRow(
                        title: section.title,
                        systemImage: section.systemImage,
                        isSelected: model.selectedSection == section
                    ) {
                        model.selectSection(section)
                    }
                }
            }

            Spacer(minLength: 24)

            dataFootnote
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            SettingsLink {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape")
                        .frame(width: 18)
                    Text("设置")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.thinMaterial)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.indigo.opacity(0.85), Color.blue.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("待办进展")
                    .font(.system(size: 14, weight: .semibold))
                Text("本地工作台")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dataFootnote: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("数据仅存本机", systemImage: "lock.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let lastBackupDate = model.lastBackupDate {
                Text("上次备份 \(AppFormat.backupTimestamp(lastBackupDate))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else {
                Text("尚未完成备份")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? AppTheme.accent : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? AppTheme.accent.opacity(0.13) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct StartupFailureView: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.orange)
            Text("无法启动待办进展")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button("退出应用") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(minWidth: 560, minHeight: 360)
    }
}
