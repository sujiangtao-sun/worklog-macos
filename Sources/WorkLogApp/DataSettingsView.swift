import AppKit
import Combine
import SwiftUI
import WorkLogCore

private final class DataSettingsState: ObservableObject {
    @Published var isExporting = false
}

struct DataSettingsView: View {
    let model: AppModel

    @StateObject private var state = DataSettingsState()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("数据与备份")
                    .font(.system(size: 20, weight: .semibold))
                Text("所有数据仅保存在本机，不会联网。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            pathCard
            backupCard
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 620, height: 480, alignment: .topLeading)
        .background(AppTheme.pageBackground)
        .onAppear {
            model.lastBackupDate = model.backupService.lastBackupDate()
        }
    }

    private var pathCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("存储位置")
                .font(.headline)

            pathRow(title: "数据目录", path: model.paths.rootURL.path) {
                model.revealDataDirectory()
            }
            pathRow(title: "备份目录", path: model.paths.backupsURL.path) {
                model.revealBackupsDirectory()
            }

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("数据库文件和富文本附件分开存放；导出的数据包含恢复说明。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .fill(AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .strokeBorder(AppTheme.borderColor, lineWidth: 1)
        )
    }

    private var backupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本地备份")
                    .font(.headline)
                Spacer()
                if let lastBackupDate = model.lastBackupDate {
                    Text("上次备份：\(AppFormat.backupTimestamp(lastBackupDate))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("尚未备份")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("每天首次启动或重新激活应用时自动备份一次，保留最近 7 份。备份包含数据库与图片附件。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    Task { _ = await model.createBackupNow() }
                } label: {
                    if model.isBackingUp {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("备份中…")
                        }
                    } else {
                        Text("立即备份")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBackingUp)

                Button("导出数据…") {
                    exportData()
                }
                .disabled(model.isBackingUp || state.isExporting)

                Spacer()
            }

            if let status = model.backupStatusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .fill(AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .strokeBorder(AppTheme.borderColor, lineWidth: 1)
        )
    }

    private func pathRow(title: String, path: String, reveal: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(path)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("显示") {
                reveal()
            }
            .controlSize(.small)
        }
    }

    private func exportData() {
        let panel = NSOpenPanel()
        panel.title = "选择导出位置"
        panel.message = "选择一个文件夹用于存放导出的数据和恢复说明"
        panel.prompt = "导出到此处"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let parentURL = panel.url else { return }

        state.isExporting = true
        Task {
            if let exportedURL = await model.exportData(to: parentURL) {
                model.revealInFinder(exportedURL)
            }
            state.isExporting = false
        }
    }
}
