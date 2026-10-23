import Combine
import SwiftUI
import WorkLogCore

@MainActor
private final class WorkTaskEditState: ObservableObject {
    @Published var title: String
    @Published var plannedAt: Date
    @Published var isSaving = false
    @Published var showDiscardDialog = false
    @Published var isMaximized = false

    let initialTitle: String
    let initialPlannedAt: Date
    let initialContent: NSAttributedString
    let editor: RichTextController

    init(title: String, plannedAt: Date, content: NSAttributedString) {
        self.title = title
        self.plannedAt = plannedAt
        self.initialTitle = title
        self.initialPlannedAt = plannedAt
        self.initialContent = content
        self.editor = RichTextController(initialContent: content)
    }
}

struct WorkTaskEditSheet: View {
    let model: AppModel
    let task: WorkTask?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var ui: WorkTaskEditState
    @FocusState private var titleFocused: Bool

    @MainActor
    init(model: AppModel, task: WorkTask?) {
        self.model = model
        self.task = task

        let content: NSAttributedString
        if let task {
            content = model.attributedContent(for: task)
        } else {
            content = NSAttributedString(string: "")
        }

        let plannedAt = task?.plannedAt ?? Self.defaultPlannedAt
        _ui = StateObject(
            wrappedValue: WorkTaskEditState(
                title: task?.title ?? "",
                plannedAt: plannedAt,
                content: content
            )
        )
    }

    private var trimmedTitle: String {
        ui.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sheetSize: CGSize {
        guard ui.isMaximized else {
            return CGSize(width: 740, height: 660)
        }

        let visible = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return CGSize(
            width: min(1120, max(740, visible.width - 80)),
            height: min(780, max(660, visible.height - 80))
        )
    }

    private var editorHeight: CGFloat {
        ui.isMaximized ? max(380, sheetSize.height - 340) : 290
    }

    private var hasChanges: Bool {
        let calendar = Calendar.autoupdatingCurrent
        if ui.title != ui.initialTitle {
            return true
        }
        if !calendar.isDate(ui.plannedAt, equalTo: ui.initialPlannedAt, toGranularity: .minute) {
            return true
        }
        return !ui.editor.currentContent.isEqual(to: ui.initialContent)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let message = model.errorMessage {
                        InlineErrorMessage(message: message) {
                            model.clearError()
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        FormLabel(title: "工作内容标题", required: true)
                        TextField("例如：完成 Q4 方案评审", text: $ui.title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, weight: .medium))
                            .focused($titleFocused)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(AppTheme.cardBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(AppTheme.borderColor, lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        FormLabel(title: "计划完成时间", required: true)
                        DatePicker(
                            "",
                            selection: $ui.plannedAt,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        FormLabel(
                            title: "工作内容",
                            hint: "富文本，可在本机插入图片，支持粘贴与拖拽"
                        )
                        RichTextEditorView(controller: ui.editor, editorHeight: editorHeight)
                    }
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(width: sheetSize.width, height: sheetSize.height)
        .background(AppTheme.pageBackground)
        .onAppear {
            titleFocused = true
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
                Text(task == nil ? "新建工作项" : "编辑工作项")
                    .font(.system(size: 17, weight: .semibold))
                Text("标题、计划时间、富文本与图片都会保存在本机")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            HStack(spacing: 8) {
                if let task {
                    StatusBadge(
                        tone: model.workStatus(for: task).tone,
                        text: model.workStatus(for: task).label
                    )
                }

                Button {
                    ui.isMaximized.toggle()
                } label: {
                    Label(
                        ui.isMaximized ? "还原" : "最大化",
                        systemImage: ui.isMaximized
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right"
                    )
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(ui.isMaximized ? "还原编辑窗口" : "最大化编辑窗口")
                .accessibilityLabel(ui.isMaximized ? "还原编辑窗口" : "最大化编辑窗口")
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
            .disabled(trimmedTitle.isEmpty || ui.isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }

    private func save() {
        guard !trimmedTitle.isEmpty, !ui.isSaving else { return }

        let content = ui.editor.currentContent
        ui.isSaving = true

        Task {
            let success: Bool
            if let task {
                success = await model.updateWorkTask(
                    task,
                    title: trimmedTitle,
                    plannedAt: ui.plannedAt,
                    richContent: content
                )
            } else {
                success = await model.createWorkTask(
                    title: trimmedTitle,
                    plannedAt: ui.plannedAt,
                    richContent: content
                )
            }
            ui.isSaving = false
            if success {
                dismiss()
            }
        }
    }

    private static var defaultPlannedAt: Date {
        let calendar = Calendar.autoupdatingCurrent
        let base = calendar.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: base) ?? base
    }
}
