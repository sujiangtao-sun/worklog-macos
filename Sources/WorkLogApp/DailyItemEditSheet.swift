import Combine
import SwiftUI
import WorkLogCore

private final class DailyEditState: ObservableObject {
    @Published var content: String
    @Published var plannedAt: Date
    @Published var isCompleted: Bool
    @Published var actualAt: Date
    @Published var difficulty: String
    @Published var feedback: String
    @Published var isSaving = false
    @Published var showDiscardDialog = false
    @Published var showDatePicker = false

    init(item: DailyItem) {
        content = item.content
        plannedAt = item.plannedAt
        isCompleted = item.isCompleted
        actualAt = item.actualAt ?? Date()
        difficulty = item.difficulty
        feedback = item.feedback
    }
}

struct DailyItemEditSheet: View {
    let model: AppModel
    let original: DailyItem

    @Environment(\.dismiss) private var dismiss
    @StateObject private var ui: DailyEditState

    init(model: AppModel, item: DailyItem) {
        self.model = model
        self.original = item
        _ui = StateObject(wrappedValue: DailyEditState(item: item))
    }

    private var trimmedContent: String {
        ui.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedPlanDay: DayKey {
        CalendarSupport.dayKey(for: ui.plannedAt)
    }

    private var draftStatus: DailyStatus {
        var draft = original
        draft.planDate = selectedPlanDay
        draft.plannedAt = ui.plannedAt
        draft.content = ui.content
        draft.difficulty = ui.difficulty
        draft.feedback = ui.feedback
        draft.actualAt = ui.isCompleted ? ui.actualAt : nil
        return model.dailyStatus(for: draft)
    }

    private var hasChanges: Bool {
        let calendar = Calendar.autoupdatingCurrent

        if ui.content != original.content
            || ui.difficulty != original.difficulty
            || ui.feedback != original.feedback
            || ui.isCompleted != original.isCompleted
            || !calendar.isDate(ui.plannedAt, equalTo: original.plannedAt, toGranularity: .minute) {
            return true
        }

        if ui.isCompleted {
            guard let originalActual = original.actualAt else { return true }
            return abs(ui.actualAt.timeIntervalSince(originalActual)) >= 60
        }
        return false
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

                    fieldLabel("事项内容", isRequired: true)
                    multilineField(
                        prompt: "写下要完成的事项，支持多行与回车换行",
                        text: $ui.content,
                        height: 120
                    )

                    schedulingSection
                    completionSection

                    fieldLabel("难点")
                    multilineField(
                        prompt: "选填：可能阻碍完成的问题、依赖或风险",
                        text: $ui.difficulty,
                        height: 78
                    )

                    fieldLabel("结果反馈")
                    multilineField(
                        prompt: "选填：完成后记录结果、结论或后续动作",
                        text: $ui.feedback,
                        height: 78
                    )
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(width: 580, height: 600)
        .background(AppTheme.pageBackground)
        .interactiveDismissDisabled(hasChanges)
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
                Text("编辑事项")
                    .font(.system(size: 17, weight: .semibold))
                Text(AppFormat.dayShortTitle(for: selectedPlanDay))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !trimmedContent.isEmpty {
                StatusDot(tone: draftStatus.tone, label: draftStatus.label)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var schedulingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("计划完成时间")

            HStack(spacing: 10) {
                Button {
                    ui.showDatePicker.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(AppFormat.dayShortTitle(for: selectedPlanDay))
                            .font(.system(size: 13))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(AppTheme.borderColor, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("选择计划日期")
                .accessibilityLabel("选择计划日期")
                .popover(isPresented: $ui.showDatePicker) {
                    VStack(alignment: .leading, spacing: 6) {
                        DatePicker(
                            "",
                            selection: planDateBinding,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding(.horizontal, 2)

                        Divider()

                        HStack(spacing: 8) {
                            Text(AppFormat.dayShortTitle(for: selectedPlanDay))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 12)
                            Button("完成") {
                                ui.showDatePicker = false
                            }
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding(8)
                    .fixedSize()
                }

                HStack(spacing: 6) {
                    Picker("", selection: hourBinding) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d", hour))
                                .tag(hour)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 72)
                    .accessibilityLabel("小时")

                    Text("时")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Picker("", selection: minuteBinding) {
                        ForEach(0..<60, id: \.self) { minute in
                            Text(String(format: "%02d", minute))
                                .tag(minute)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 72)
                    .accessibilityLabel("分钟")

                    Text("分")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if selectedPlanDay == original.planDate {
                Text("可分别选择日期、小时和分钟")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                Text("保存后事项会移到新日期的列表")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.accent)
            }
        }
    }

    private var completionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("已完成", isOn: $ui.isCompleted)
                .toggleStyle(.checkbox)
                .font(.subheadline.weight(.medium))

            if ui.isCompleted {
                HStack(spacing: 10) {
                    DatePicker(
                        "实际完成时间",
                        selection: $ui.actualAt,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)

                    Button("现在") {
                        ui.actualAt = Date()
                    }
                    .controlSize(.small)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(AppTheme.borderColor, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.16), value: ui.isCompleted)
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
            .disabled(trimmedContent.isEmpty || ui.isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }

    private func fieldLabel(_ title: String, isRequired: Bool = false) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if isRequired {
                Text("*")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
    }

    private func multilineField(
        prompt: String,
        text: Binding<String>,
        height: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(prompt)
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }

            TextEditor(text: text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(4)
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.borderColor, lineWidth: 1)
        )
    }

    private var planDateBinding: Binding<Date> {
        Binding(
            get: { ui.plannedAt },
            set: { newDate in
                updateDate(newDate)
            }
        )
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: {
                Calendar.autoupdatingCurrent.component(.hour, from: ui.plannedAt)
            },
            set: { newHour in
                updateTime(hour: newHour, minute: nil)
            }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: {
                Calendar.autoupdatingCurrent.component(.minute, from: ui.plannedAt)
            },
            set: { newMinute in
                updateTime(hour: nil, minute: newMinute)
            }
        )
    }

    private func updateDate(_ newDate: Date) {
        let calendar = Calendar.autoupdatingCurrent
        let time = calendar.dateComponents([.hour, .minute], from: ui.plannedAt)
        var components = calendar.dateComponents([.year, .month, .day], from: newDate)
        components.hour = time.hour ?? 18
        components.minute = time.minute ?? 0
        components.second = 0
        ui.plannedAt = calendar.date(from: components) ?? ui.plannedAt
    }

    private func updateTime(hour: Int?, minute: Int?) {
        let calendar = Calendar.autoupdatingCurrent
        let currentTime = calendar.dateComponents([.hour, .minute], from: ui.plannedAt)
        var components = calendar.dateComponents([.year, .month, .day], from: ui.plannedAt)
        components.hour = hour ?? currentTime.hour
        components.minute = minute ?? currentTime.minute
        components.second = 0
        ui.plannedAt = calendar.date(from: components) ?? ui.plannedAt
    }

    private func save() {
        guard !trimmedContent.isEmpty, !ui.isSaving else { return }

        var updated = original
        updated.content = ui.content
        updated.planDate = selectedPlanDay
        updated.plannedAt = ui.plannedAt
        updated.actualAt = ui.isCompleted ? ui.actualAt : nil
        updated.difficulty = ui.difficulty
        updated.feedback = ui.feedback

        ui.isSaving = true
        Task {
            let success = await model.saveDailyItem(updated)
            ui.isSaving = false
            if success {
                dismiss()
            }
        }
    }
}
