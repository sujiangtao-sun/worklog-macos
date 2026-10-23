import AppKit
import SwiftUI
import WorkLogCore

enum StatusTone {
    case green
    case blue
    case red
    case gray

    var color: Color {
        switch self {
        case .green: .green
        case .blue: .blue
        case .red: .red
        case .gray: .secondary
        }
    }
}

extension DailyStatus {
    var tone: StatusTone {
        switch self {
        case .completed: .green
        case .pendingToday: .blue
        case .missed: .red
        case .upcoming: .gray
        }
    }

    var label: String {
        switch self {
        case .completed: "已完成"
        case .pendingToday: "待完成"
        case .missed: "未完成"
        case .upcoming: "未开始"
        }
    }
}

extension WorkStatus {
    var tone: StatusTone {
        switch self {
        case .completed, .completedLate: .green
        case .inProgress: .blue
        case .overdue: .red
        }
    }

    var label: String {
        switch self {
        case .completed:
            "已完成"
        case .completedLate(let days):
            days == 0 ? "超时完成" : "逾期 \(days) 天完成"
        case .inProgress:
            "未完成"
        case .overdue(let days):
            days == 0 ? "今日已超时" : "逾期 \(days) 天"
        }
    }
}

enum AppTheme {
    static let accent = Color.indigo
    static let cornerRadius: CGFloat = 10
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let pageBackground = Color(nsColor: .windowBackgroundColor)
    static let panelBackground = Color(nsColor: .underPageBackgroundColor)
    static let borderColor = Color.primary.opacity(0.07)
}

struct StatusDot: View {
    let tone: StatusTone
    var label: String?
    var dotSize: CGFloat = 8

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tone.color)
                .frame(width: dotSize, height: dotSize)
            if let label {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tone.color)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "状态")
    }
}

struct StatusBadge: View {
    let tone: StatusTone
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tone.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(tone.color.opacity(0.12)))
            .accessibilityLabel(text)
    }
}

@MainActor
enum AppFormat {
    private static let locale = Locale(identifier: "zh_CN")

    private static let timeFormatter = makeFormatter("HH:mm")
    private static let monthDayTimeFormatter = makeFormatter("M月d日 HH:mm")
    private static let fullDateTimeFormatter = makeFormatter("yyyy年M月d日 HH:mm")
    private static let dateTitleFormatter = makeFormatter("yyyy年M月d日")
    private static let shortDateTitleFormatter = makeFormatter("M月d日")
    private static let weekdayFormatter = makeFormatter("EEEE")
    private static let backupFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func shortDateTime(_ date: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            return monthDayTimeFormatter.string(from: date)
        }
        return fullDateTimeFormatter.string(from: date)
    }

    static func fullDateTime(_ date: Date) -> String {
        fullDateTimeFormatter.string(from: date)
    }

    static func dayTitle(for day: DayKey) -> String {
        guard let date = CalendarSupport.date(for: day) else { return day.rawValue }
        return "\(dateTitleFormatter.string(from: date)) \(weekdayFormatter.string(from: date))"
    }

    static func dayShortTitle(for day: DayKey) -> String {
        guard let date = CalendarSupport.date(for: day) else { return day.rawValue }
        return "\(shortDateTitleFormatter.string(from: date)) \(weekdayFormatter.string(from: date))"
    }

    static func monthTitle(year: Int, month: Int) -> String {
        "\(year)年\(month)月"
    }

    static func monthWithYear(_ date: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return monthTitle(year: year, month: month)
    }

    static func backupTimestamp(_ date: Date) -> String {
        backupFormatter.string(from: date)
    }

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = format
        return formatter
    }
}

enum CalendarMath {
    static let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]
    static let selectableYears = Array(2000...2100)

    static var calendar: Calendar {
        Calendar.autoupdatingCurrent
    }

    static func monthGrid(year: Int, month: Int) -> [DayKey?] {
        guard let range = CalendarSupport.monthDayRange(year: year, month: month),
              let firstDate = CalendarSupport.date(for: range.first) else {
            return []
        }

        let weekday = calendar.component(.weekday, from: firstDate)
        let leadingCount = (weekday + 5) % 7
        guard let days = calendar.range(of: .day, in: .month, for: firstDate) else {
            return []
        }

        var cells = Array<DayKey?>(repeating: nil, count: leadingCount)
        for offset in 0..<days.count {
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstDate) else { continue }
            cells.append(CalendarSupport.dayKey(for: date))
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    static func dayNumber(for day: DayKey) -> Int? {
        guard let last = day.rawValue.split(separator: "-").last else { return nil }
        return Int(last)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        guard let range = CalendarSupport.monthDayRange(year: year, month: month),
              let firstDate = CalendarSupport.date(for: range.first),
              let days = calendar.range(of: .day, in: .month, for: firstDate) else {
            return 0
        }
        return days.count
    }
}
