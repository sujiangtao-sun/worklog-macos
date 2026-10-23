import Combine
import SwiftUI
import WorkLogCore

private enum WorkFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case overdue
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .active: "未完成"
        case .overdue: "逾期"
        case .completed: "已完成"
        }
    }

    func matches(_ status: WorkStatus) -> Bool {
        switch self {
        case .all:
            return true
        case .active:
            return !status.isCompleted
        case .overdue:
            return status.isOverdue
        case .completed:
            return status.isCompleted
        }
    }
}

private enum WorkDeletionTarget: Identifiable {
    case task(WorkTask)
    case progress(WorkProgress)

    var id: String {
        switch self {
        case .task(let task): "task-\(task.id.uuidString)"
        case .progress(let progress): "progress-\(progress.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .task: "删除工作项？"
        case .progress: "删除这条进展？"
        }
    }

    var message: String {
        switch self {
        case .task(let task):
            "“\(task.title)”及其全部进展和图片附件都会被删除，此操作不可撤销。"
        case .progress:
            "这条进展记录及其图片附件都会被删除，此操作不可撤销。"
        }
    }
}

private final class WorkWorkspaceState: ObservableObject {
    @Published var filter: WorkFilter = .all
    @Published var showingNewTask = false
    @Published var editingTask: WorkTask?
    @Published var showingAddProgress = false
    @Published var editingProgress: WorkProgress?
    @Published var pendingDeletion: WorkDeletionTarget?
}

struct WorkWorkspaceView: View {
    let model: AppModel

    @StateObject private var ui = WorkWorkspaceState()

    private var filteredTasks: [WorkTask] {
        model.workTasks.filter { ui.filter.matches(model.workStatus(for: $0)) }
    }

    var body: some View {
        HStack(spacing: 0) {
            WorkListPane(
                model: model,
                tasks: filteredTasks,
                filter: $ui.filter,
                onSelect: { task in
                    Task { await model.selectWorkTask(task.id) }
                },
                onCreate: {
                    ui.showingNewTask = true
                }
            )
            .frame(minWidth: 330, idealWidth: 360, maxWidth: 400)

            Divider()

            WorkDetailPane(
                model: model,
                task: model.selectedWorkTask,
                progress: model.progressEntries,
                onCreate: {
                    ui.showingNewTask = true
                },
                onEdit: { task in
                    ui.editingTask = task
                },
                onDelete: { task in
                    ui.pendingDeletion = .task(task)
                },
                onToggleCompletion: { task, completed in
                    Task { await model.setWorkTaskCompleted(task, completed: completed) }
                },
                onActualTimeChange: { task, date in
                    Task { _ = await model.updateWorkActualTime(task, actualAt: date) }
                },
                onAddProgress: {
                    ui.showingAddProgress = true
                },
                onEditProgress: { progress in
                    ui.editingProgress = progress
                },
                onDeleteProgress: { progress in
                    ui.pendingDeletion = .progress(progress)
                }
            )
            .frame(minWidth: 520, maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
        .onReceive(NotificationCenter.default.publisher(for: .workLogCreateItem)) { _ in
            guard ui.editingTask == nil,
                  ui.editingProgress == nil,
                  !ui.showingAddProgress,
                  !ui.showingNewTask else {
                return
            }
            ui.showingNewTask = true
        }
        .onChange(of: ui.filter) { _, newFilter in
            guard let task = model.selectedWorkTask,
                  !newFilter.matches(model.workStatus(for: task)) else {
                return
            }
            let nextTaskID = filteredTasks.first?.id
            Task { await model.selectWorkTask(nextTaskID) }
        }
        .sheet(isPresented: $ui.showingNewTask) {
            WorkTaskEditSheet(model: model, task: nil)
        }
        .sheet(item: $ui.editingTask) { task in
            WorkTaskEditSheet(model: model, task: task)
        }
        .sheet(isPresented: $ui.showingAddProgress) {
            if let task = model.selectedWorkTask {
                ProgressEditSheet(model: model, task: task, progress: nil)
            }
        }
        .sheet(item: $ui.editingProgress) { progress in
            if let task = model.selectedWorkTask {
                ProgressEditSheet(model: model, task: task, progress: progress)
            }
        }
        .alert(
            ui.pendingDeletion?.title ?? "确认删除",
            isPresented: deletionPresented,
            presenting: ui.pendingDeletion
        ) { target in
            Button("删除", role: .destructive) {
                performDelete(target)
            }
            Button("取消", role: .cancel) {
                ui.pendingDeletion = nil
            }
        } message: { target in
            Text(target.message)
        }
    }

    private var deletionPresented: Binding<Bool> {
        Binding(
            get: { ui.pendingDeletion != nil },
            set: { newValue in
                if !newValue {
                    ui.pendingDeletion = nil
                }
            }
        )
    }

    private func performDelete(_ target: WorkDeletionTarget) {
        ui.pendingDeletion = nil
        switch target {
        case .task(let task):
            Task { await model.deleteWorkTask(task) }
        case .progress(let progress):
            Task { await model.deleteProgress(progress) }
        }
    }
}

private struct WorkListPane: View {
    let model: AppModel
    let tasks: [WorkTask]
    @Binding var filter: WorkFilter
    let onSelect: (WorkTask) -> Void
    let onCreate: () -> Void

    private var incompleteCount: Int {
        model.workTasks.filter { !model.workStatus(for: $0).isCompleted }.count
    }

    private var overdueCount: Int {
        model.workTasks.filter { model.workStatus(for: $0).isOverdue }.count
    }

    private var summary: String {
        if model.workTasks.isEmpty {
            return "暂无工作项"
        }
        return "\(incompleteCount) 项未完成 · \(overdueCount) 项逾期"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("工作跟踪")
                        .font(.system(size: 20, weight: .semibold))
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    onCreate()
                } label: {
                    Label("新建", systemImage: "plus")
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .help("新建工作项（⌘N）")
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 12)

            HStack(spacing: 6) {
                ForEach(WorkFilter.allCases) { option in
                    FilterChip(
                        title: option.title,
                        isSelected: filter == option
                    ) {
                        filter = option
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)

            Divider()

            if tasks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(tasks) { task in
                            WorkTaskRow(
                                model: model,
                                task: task,
                                isSelected: model.selectedWorkTaskID == task.id
                            ) {
                                onSelect(task)
                            }
                        }
                    }
                    .padding(8)
                    .padding(.bottom, 10)
                }
                .scrollIndicators(.automatic)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppTheme.panelBackground)
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "tray")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Text(emptyMessage)
                .font(.subheadline.weight(.medium))
            Text(filter == .all ? "点击右上角“新建”添加第一项工作。" : "试试切换到其他筛选条件。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    private var emptyMessage: String {
        switch filter {
        case .all: "还没有工作项"
        case .active: "没有未完成的工作"
        case .overdue: "没有逾期工作"
        case .completed: "还没有已完成工作"
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(isSelected ? AppTheme.accent : Color.secondary)
                .background(
                    Capsule()
                        .fill(isSelected ? AppTheme.accent.opacity(0.14) : Color.primary.opacity(0.045))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct WorkTaskRow: View {
    let model: AppModel
    let task: WorkTask
    let isSelected: Bool
    let action: () -> Void

    private var status: WorkStatus {
        model.workStatus(for: task)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 7) {
                    Circle()
                        .fill(status.tone.color)
                        .frame(width: 7, height: 7)
                        .padding(.top, 4)

                    Text(task.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                    if status.isOverdue {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                            .padding(.top, 3)
                    }
                }

                HStack(spacing: 6) {
                    Label("计划 \(AppFormat.shortDateTime(task.plannedAt))", systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(status.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(status.tone.color)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? AppTheme.accent.opacity(0.13) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isSelected ? AppTheme.accent.opacity(0.25) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(task.title)，\(status.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct WorkDetailPane: View {
    let model: AppModel
    let task: WorkTask?
    let progress: [WorkProgress]
    let onCreate: () -> Void
    let onEdit: (WorkTask) -> Void
    let onDelete: (WorkTask) -> Void
    let onToggleCompletion: (WorkTask, Bool) -> Void
    let onActualTimeChange: (WorkTask, Date) -> Void
    let onAddProgress: () -> Void
    let onEditProgress: (WorkProgress) -> Void
    let onDeleteProgress: (WorkProgress) -> Void

    var body: some View {
        if let task {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(task)
                    completionCard(task)
                    contentSection(task)
                    progressSection(task)
                }
                .frame(maxWidth: 980, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .background(AppTheme.pageBackground)
        } else {
            emptyState
        }
    }

    private func header(_ task: WorkTask) -> some View {
        let status = model.workStatus(for: task)

        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                StatusBadge(tone: status.tone, text: status.label)
                Text(task.title)
                    .font(.system(size: 24, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                Label(
                    "计划完成 \(AppFormat.fullDateTime(task.plannedAt))",
                    systemImage: "calendar"
                )
                .font(.callout)
                .foregroundStyle(status.isOverdue ? Color.red : Color.secondary)
            }

            Spacer(minLength: 16)

            Button {
                onEdit(task)
            } label: {
                Label("编辑", systemImage: "square.and.pencil")
            }
            .controlSize(.small)

            Menu {
                Button("编辑工作项", systemImage: "square.and.pencil") {
                    onEdit(task)
                }
                Divider()
                Button("删除工作项", systemImage: "trash", role: .destructive) {
                    onDelete(task)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多操作")
        }
    }

    private func completionCard(_ task: WorkTask) -> some View {
        let status = model.workStatus(for: task)

        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: task.isCompleted ? "checkmark.seal.fill" : "circle.dashed")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(status.tone.color)

            VStack(alignment: .leading, spacing: 3) {
                Text(completionTitle(task, status: status))
                    .font(.system(size: 13, weight: .semibold))
                Text(completionDetail(task, status: status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if task.isCompleted {
                DatePicker(
                    "实际完成",
                    selection: actualTimeBinding(task),
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .font(.caption)
                .fixedSize()

                Button("撤销完成") {
                    onToggleCompletion(task, false)
                }
                .controlSize(.small)
            } else {
                Button {
                    onToggleCompletion(task, true)
                } label: {
                    Label("标记完成", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .fill(AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .strokeBorder(AppTheme.borderColor, lineWidth: 1)
        )
    }

    private func completionTitle(_ task: WorkTask, status: WorkStatus) -> String {
        if task.isCompleted {
            return status.label
        }
        if status.isOverdue {
            return "当前工作已逾期"
        }
        return "当前工作未完成"
    }

    private func completionDetail(_ task: WorkTask, status: WorkStatus) -> String {
        if task.isCompleted, let actualAt = task.actualAt {
            return "实际完成于 \(AppFormat.fullDateTime(actualAt))"
        }
        if status.isOverdue {
            return "计划完成时间已过，请补充进展、调整计划或尽快完成。"
        }
        return "到达计划时间前，可随时补充多条进展记录。"
    }

    private func contentSection(_ task: WorkTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("工作内容")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    onEdit(task)
                } label: {
                    Label("编辑内容", systemImage: "square.and.pencil")
                        .font(.caption)
                }
                .controlSize(.small)
            }

            if hasRichContent(path: task.contentPath, plain: task.contentPlain) {
                RichTextDisplay(
                    store: model.richTextStore,
                    relativePath: task.contentPath,
                    fallbackPlainText: task.contentPlain,
                    revision: task.updatedAt
                )
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground)
            } else {
                placeholderRow(text: "尚未填写详细内容，点击“编辑内容”补充文字或图片。")
            }
        }
    }

    private func progressSection(_ task: WorkTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("进展反馈")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(progress.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.05)))
                Spacer()
                Button {
                    onAddProgress()
                } label: {
                    Label("添加进展", systemImage: "plus")
                        .font(.caption)
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }

            if progress.isEmpty {
                placeholderRow(text: "还没有进展记录。点击“添加进展”记录当前状态。")
            } else {
                VStack(spacing: 10) {
                    ForEach(progress) { entry in
                        ProgressCard(
                            store: model.richTextStore,
                            entry: entry,
                            onEdit: { onEditProgress(entry) },
                            onDelete: { onDeleteProgress(entry) }
                        )
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(AppTheme.accent.opacity(0.7))
            Text("选择或新建一个工作项")
                .font(.headline)
            Text("在这里查看工作内容、跟踪进展并记录逾期情况。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                onCreate()
            } label: {
                Label("新建工作项", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.pageBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
            .fill(AppTheme.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.borderColor, lineWidth: 1)
            )
    }

    private func placeholderRow(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "text.alignleft")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func actualTimeBinding(_ task: WorkTask) -> Binding<Date> {
        Binding(
            get: { task.actualAt ?? Date() },
            set: { newValue in
                onActualTimeChange(task, newValue)
            }
        )
    }

    private func hasRichContent(path: String?, plain: String) -> Bool {
        path != nil || !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct ProgressCard: View {
    let store: RichTextStore
    let entry: WorkProgress
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var wasEdited: Bool {
        entry.updatedAt.timeIntervalSince(entry.createdAt) > 60
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(AppTheme.accent.opacity(0.8))
                    .frame(width: 6, height: 6)
                Text(AppFormat.shortDateTime(entry.createdAt))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if wasEdited {
                    Text("已编辑")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.05)))
                }
                Spacer()
                Button("编辑进展", action: onEdit)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
                Menu {
                    Button("编辑进展", systemImage: "square.and.pencil", action: onEdit)
                    Divider()
                    Button("删除进展", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            RichTextDisplay(
                store: store,
                relativePath: entry.contentPath,
                fallbackPlainText: entry.contentPlain,
                revision: entry.updatedAt
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .fill(AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .strokeBorder(AppTheme.borderColor, lineWidth: 1)
        )
        .contextMenu {
            Button("编辑进展", action: onEdit)
            Button("删除进展", role: .destructive, action: onDelete)
        }
    }
}
