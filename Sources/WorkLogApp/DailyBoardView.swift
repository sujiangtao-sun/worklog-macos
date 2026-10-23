import Combine
import SwiftUI
import WorkLogCore

private final class DailyBoardState: ObservableObject {
    @Published var newContent = ""
    @Published var editingItem: DailyItem?
    @Published var itemToDelete: DailyItem?
    @Published var isAdding = false
}

struct DailyBoardView: View {
    let model: AppModel

    @StateObject private var ui = DailyBoardState()
    @FocusState private var quickAddFocused: Bool

    private var completedCount: Int {
        model.dailyItems.filter(\.isCompleted).count
    }

    private var trimmedNewContent: String {
        ui.newContent.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            quickAddBar
            Divider()
                .padding(.top, 16)
                .padding(.bottom, 14)
            content
        }
        .padding(24)
        .background(AppTheme.pageBackground)
        .onReceive(NotificationCenter.default.publisher(for: .workLogCreateItem)) { _ in
            quickAddFocused = true
        }
        .sheet(item: $ui.editingItem) { item in
            DailyItemEditSheet(model: model, item: item)
        }
        .alert("删除这条事项？", isPresented: deletePresented, presenting: ui.itemToDelete) { item in
            Button("删除", role: .destructive) {
                Task { await model.deleteDailyItem(item) }
                ui.itemToDelete = nil
            }
            Button("取消", role: .cancel) {
                ui.itemToDelete = nil
            }
        } message: { item in
            Text(item.content)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(AppFormat.dayTitle(for: model.selectedDay))
                        .font(.system(size: 22, weight: .semibold))
                    if model.selectedDayIsToday {
                        Text("今天")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(AppTheme.accent.opacity(0.12)))
                    }
                }

                HStack(spacing: 10) {
                    Text("共 \(model.dailyItems.count) 项 · 已完成 \(completedCount) 项")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if model.dailyItems.count > 0 {
                        ProgressView(
                            value: Double(completedCount),
                            total: Double(model.dailyItems.count)
                        )
                        .progressViewStyle(.linear)
                        .tint(.green)
                        .frame(width: 112)
                    }
                }
            }

            Spacer(minLength: 16)

            Button {
                model.toggleCalendarPanel()
            } label: {
                Label(
                    model.isCalendarPanelVisible ? "隐藏日历" : "显示日历",
                    systemImage: model.isCalendarPanelVisible ? "sidebar.left" : "calendar"
                )
                .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(model.isCalendarPanelVisible ? "隐藏左侧日历面板，让待办列表更宽" : "显示左侧日历面板")
            .accessibilityLabel(model.isCalendarPanelVisible ? "隐藏日历面板" : "显示日历面板")
        }
    }

    private var quickAddBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.accent)

                TextField("添加一条事项，回车确认", text: $ui.newContent)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($quickAddFocused)
                    .onSubmit(addItem)

                Button {
                    addItem()
                } label: {
                    if ui.isAdding {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("添加")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(trimmedNewContent.isEmpty || ui.isAdding)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .strokeBorder(
                        quickAddFocused ? AppTheme.accent.opacity(0.45) : AppTheme.borderColor,
                        lineWidth: 1
                    )
            )

            Text("默认计划完成时间为 18:00，可在事项的编辑面板中补充时间、难点与结果反馈")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)
        }
        .padding(.top, 18)
    }

    @ViewBuilder
    private var content: some View {
        if model.dailyItems.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.dailyItems) { item in
                        DailyItemCard(
                            model: model,
                            item: item,
                            onEdit: { ui.editingItem = item },
                            onDelete: { ui.itemToDelete = item }
                        )
                    }
                }
                .padding(.bottom, 18)
            }
            .scrollIndicators(.automatic)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(AppTheme.accent.opacity(0.75))
            Text("这一天还没有事项")
                .font(.headline)
            Text("在上方输入内容，按回车即可逐条添加。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    private var deletePresented: Binding<Bool> {
        Binding(
            get: { ui.itemToDelete != nil },
            set: { newValue in
                if !newValue {
                    ui.itemToDelete = nil
                }
            }
        )
    }

    private func addItem() {
        guard !trimmedNewContent.isEmpty, !ui.isAdding else { return }
        let content = ui.newContent
        ui.isAdding = true

        Task {
            let success = await model.quickAddDailyItem(content)
            if success {
                ui.newContent = ""
            }
            ui.isAdding = false
            quickAddFocused = true
        }
    }
}

private struct DailyItemCard: View {
    let model: AppModel
    let item: DailyItem
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var status: DailyStatus {
        model.dailyStatus(for: item)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Task { await model.toggleDailyCompletion(item) }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(item.isCompleted ? Color.green : Color.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help(item.isCompleted ? "撤销完成" : "标记完成")
            .accessibilityLabel(item.isCompleted ? "已完成，点击撤销完成" : "未完成，点击标记完成")

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(item.content)
                        .font(.system(size: 14, weight: item.isCompleted ? .regular : .medium))
                        .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                        .strikethrough(item.isCompleted, color: .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    StatusDot(tone: status.tone, label: status.label)
                        .fixedSize()
                }

                HStack(spacing: 16) {
                    Label("计划 \(AppFormat.time(item.plannedAt))", systemImage: "clock")
                    if let actualAt = item.actualAt {
                        Label("实际 \(AppFormat.shortDateTime(actualAt))", systemImage: "checkmark.circle")
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !item.difficulty.isEmpty {
                    detailLine(
                        icon: "exclamationmark.triangle",
                        title: "难点",
                        text: item.difficulty
                    )
                }

                if !item.feedback.isEmpty {
                    detailLine(
                        icon: "text.quote",
                        title: "结果反馈",
                        text: item.feedback
                    )
                }
            }

            HStack(spacing: 2) {
                Button(action: onEdit) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("编辑事项")
                .accessibilityLabel("编辑事项")

                Menu {
                    Button("编辑事项", systemImage: "square.and.pencil", action: onEdit)
                    Divider()
                    Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("更多操作")
                .accessibilityLabel("更多操作")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .fill(AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .strokeBorder(AppTheme.borderColor, lineWidth: 1)
        )
        .contextMenu {
            Button("编辑事项", action: onEdit)
            Button("删除", role: .destructive, action: onDelete)
        }
    }

    private func detailLine(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 14)
                .padding(.top, 1)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
