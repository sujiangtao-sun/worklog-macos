import Foundation

public struct StatusCalculator {
    public let calendar: Calendar

    public init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    public func dailyStatus(for item: DailyItem, now: Date = Date()) -> DailyStatus {
        dailyStatus(day: item.planDate, completed: item.isCompleted, now: now)
    }

    public func dailyStatus(day: DayKey, completed: Bool, now: Date = Date()) -> DailyStatus {
        if completed { return .completed }
        let today = CalendarSupport.dayKey(for: now, calendar: calendar)
        if day < today { return .missed }
        if day == today { return .pendingToday }
        return .upcoming
    }

    public func dayStatus(for summary: DaySummary, now: Date = Date()) -> DailyStatus? {
        guard summary.total > 0 else { return nil }
        if summary.isAllCompleted { return .completed }
        let today = CalendarSupport.dayKey(for: now, calendar: calendar)
        if summary.day < today { return .missed }
        if summary.day == today { return .pendingToday }
        return .upcoming
    }

    public func workStatus(for task: WorkTask, now: Date = Date()) -> WorkStatus {
        if let actualAt = task.actualAt {
            if actualAt > task.plannedAt {
                return .completedLate(days: overdueDayCount(from: task.plannedAt, to: actualAt))
            }
            return .completed
        }
        if task.plannedAt < now {
            return .overdue(days: overdueDayCount(from: task.plannedAt, to: now))
        }
        return .inProgress
    }

    public func overdueDayCount(from plannedAt: Date, to referenceDate: Date) -> Int {
        let start = calendar.startOfDay(for: plannedAt)
        let end = calendar.startOfDay(for: referenceDate)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(0, days)
    }
}
