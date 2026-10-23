import SwiftUI
import WorkLogCore

struct CalendarWorkspaceView: View {
    let model: AppModel

    var body: some View {
        Group {
            if model.isCalendarPanelVisible {
                HStack(spacing: 0) {
                    CalendarBrowserView(model: model)
                        .frame(width: 376)
                    Divider()
                    DailyBoardView(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                DailyBoardView(model: model)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.isCalendarPanelVisible)
    }
}

struct CalendarBrowserView: View {
    let model: AppModel

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 4),
        count: 7
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            topBar

            if model.calendarLevel == .months {
                monthsOverview
            } else {
                monthView
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.panelBackground)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var topBar: some View {
        switch model.calendarLevel {
        case .months:
            HStack(spacing: 8) {
                yearMenu
                Spacer(minLength: 8)
                CalendarIconButton(systemImage: "chevron.left", help: "上一年") {
                    model.setOverviewYear(model.calendarYear - 1)
                }
                .disabled(model.calendarYear <= CalendarMath.selectableYears.first ?? 2000)
                CalendarIconButton(systemImage: "chevron.right", help: "下一年") {
                    model.setOverviewYear(model.calendarYear + 1)
                }
                .disabled(model.calendarYear >= CalendarMath.selectableYears.last ?? 2100)
                todayButton
            }
        case .days:
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        model.showMonthsOverview()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.primary.opacity(0.06)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(model.calendarMonth)月")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("\(model.calendarYear)年")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("选择年份和月份")

                Spacer(minLength: 8)
                CalendarIconButton(systemImage: "chevron.left", help: "上个月") {
                    Task { await model.showPreviousMonth() }
                }
                todayButton
                CalendarIconButton(systemImage: "chevron.right", help: "下个月") {
                    Task { await model.showNextMonth() }
                }
            }
        }
    }

    private var yearMenu: some View {
        Menu {
            ForEach(CalendarMath.selectableYears, id: \.self) { year in
                Button {
                    model.setOverviewYear(year)
                } label: {
                    if year == model.calendarYear {
                        Label("\(year)年", systemImage: "checkmark")
                    } else {
                        Text("\(year)年")
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text("\(model.calendarYear)年")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("选择年份")
    }

    private var todayButton: some View {
        Button {
            Task { await model.goToToday() }
        } label: {
            Text("今天")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .background(
            Capsule()
                .fill(AppTheme.accent.opacity(0.1))
        )
        .foregroundStyle(AppTheme.accent)
        .help("回到今天")
    }

    private var monthsOverview: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
            spacing: 10
        ) {
            ForEach(1...12, id: \.self) { month in
                Button {
                    Task { await model.showMonth(year: model.calendarYear, month: month) }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 5) {
                            Text("\(month)月")
                                .font(.system(size: 15, weight: .semibold))
                            if isCurrentMonth(month) {
                                Text("本月")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(AppTheme.accent)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(AppTheme.accent.opacity(0.12)))
                            }
                            Spacer(minLength: 0)
                        }

                        Spacer(minLength: 0)

                        HStack {
                            Text("\(CalendarMath.daysInMonth(year: model.calendarYear, month: month)) 天")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: 86)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isCurrentMonth(month) ? AppTheme.accent.opacity(0.55) : AppTheme.borderColor,
                                lineWidth: 1
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(model.calendarYear)年\(month)月")
                .accessibilityHint("打开这个月的日历")
            }
        }
    }

    private var monthView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(CalendarMath.weekdayLabels, id: \.self) { weekday in
                    Text(weekday)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 2)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(grid.enumerated()), id: \.offset) { _, day in
                    if let day {
                        CalendarDayCell(model: model, day: day)
                    } else {
                        Color.clear
                            .frame(height: 46)
                    }
                }
            }
        }
    }

    private var grid: [DayKey?] {
        CalendarMath.monthGrid(year: model.calendarYear, month: model.calendarMonth)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("点击日期查看当天事项；点击左上角返回可切换年份与月份")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            HStack(spacing: 12) {
                legendDot(.green, "已完成")
                legendDot(.blue, "今日待办")
                legendDot(.red, "未完成")
                legendDot(.gray, "未来")
            }
        }
        .padding(.top, 6)
    }

    private func legendDot(_ tone: StatusTone, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tone.color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private func isCurrentMonth(_ month: Int) -> Bool {
        let components = Calendar.autoupdatingCurrent.dateComponents([.year, .month], from: model.now)
        return components.year == model.calendarYear && components.month == month
    }
}

private struct CalendarIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct CalendarDayCell: View {
    let model: AppModel
    let day: DayKey

    private var summary: DaySummary? {
        model.monthSummaries[day]
    }

    private var status: DailyStatus? {
        guard let summary else { return nil }
        return model.dayStatus(for: summary)
    }

    private var isSelected: Bool {
        model.selectedDay == day
    }

    private var isToday: Bool {
        model.todayKey == day
    }

    var body: some View {
        Button {
            Task { await model.selectDay(day) }
        } label: {
            VStack(spacing: 4) {
                Text("\(CalendarMath.dayNumber(for: day) ?? 0)")
                    .font(.system(size: 13, weight: isSelected || isToday ? .semibold : .regular))
                    .foregroundStyle(isSelected || isToday ? AppTheme.accent : Color.primary)

                HStack(spacing: 3) {
                    if let status {
                        Circle()
                            .fill(status.tone.color)
                            .frame(width: 5, height: 5)
                    }
                    if let summary, summary.total > 0 {
                        Text("\(summary.total)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? AppTheme.accent.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isToday && !isSelected ? AppTheme.accent.opacity(0.4) : Color.clear
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(summaryText)
        .accessibilityLabel("\(AppFormat.dayTitle(for: day))，\(summaryText)")
    }

    private var summaryText: String {
        guard let summary, summary.total > 0 else { return "无事项" }
        return "共 \(summary.total) 项，已完成 \(summary.completed) 项"
    }
}
