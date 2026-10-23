import Combine
import SwiftUI
import WorkLogCore

@MainActor
private final class ProgressEditState: ObservableObject {
    @Published var isSaving = false
    @Published var showDiscardDialog = false

    let initialContent: NSAttributedString
    let editor: RichTextController

    init(content: NSAttributedString) {
        self.initialContent = content
        self.editor = RichTextController(initialContent: content)
    }
}

struct ProgressEditSheet: View {
    let model: AppModel
    let task: WorkTask
    let progress: WorkProgress?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var ui: ProgressEditState

    @MainActor
    init(model: AppModel, task: WorkTask, progress: WorkProgress?) {
        self.model = model
        self.task = task
        self.progress = progress

        let content: NSAttributedString
        if let progress {
            content = model.attributedContent(for: progress)
        } else {
            content = NSAttributedString(string: "")
        }

        _ui = StateObject(wrappedValue: ProgressEditState(content: content))
    }

    private var hasChanges: Bool {
        !ui.editor.currentContent.isEqual(to: ui.initialContent)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let message = model.errorMessage {
                        InlineErrorMessage(message: message) {
                            model.clearError()
                        }
                    }

                    FormLabel(
                        title: progress == nil ? "本次进展" : "编辑进展",
                        hint: "富文本，可插入图片；保存时自动记录当前时间"
                    )

                    RichTextEditorView(controller: ui.editor, editorHeight: 300)

                    Text("每条进展独立保存；编辑已有进展会保留原始创建时间并标记为已编辑。")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(width: 700, height: 540)
        .background(AppTheme.pageBackground)
        .onAppear {
            DispatchQueue.main.async {
                ui.editor.focus()
            }
        }
        .confirmationDialog("放弃未保存的修改？", isPresented: $ui.showDiscardDialog) {
            Button("放弃修改", role: .destructive) {
                dismiss()
            }
            Button("继续编辑", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(progress == nil ? "添加进展" : "编辑进展")
                    .font(.system(size: 17, weight: .semibold))
                Text(task.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let progress {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("记录于 \(AppFormat.fullDateTime(progress.createdAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if progress.updatedAt.timeIntervalSince(progress.createdAt) > 60 {
                        Text("已编辑")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("⌘S 保存")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("取消") {
                if hasChanges {
                    ui.showDiscardDialog = true
                } else {
                    dismiss()
                }
            }
            .keyboardShortcut(.cancelAction)

            Button {
                save()
            } label: {
                if ui.isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 48)
                } else {
                    Text("保存")
                        .frame(width: 48)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(ui.isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }

    private func save() {
        guard !ui.isSaving else { return }
        let content = ui.editor.currentContent
        ui.isSaving = true

        Task {
            let success: Bool
            if let progress {
                success = await model.updateProgress(progress, richContent: content)
            } else {
                success = await model.addProgress(to: task, richContent: content)
            }
            ui.isSaving = false
            if success {
                dismiss()
            }
        }
    }
}
