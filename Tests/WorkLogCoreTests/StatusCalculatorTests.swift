import Foundation
import Testing
@testable import WorkLogCore

@Suite("Status calculation")
struct StatusCalculatorTests {
    private var calculator: StatusCalculator {
        StatusCalculator(calendar: TestDates.defaultCalendar)
    }

    private var now: Date {
        TestDates.date(2026, 10, 23, hour: 12)
    }

    @Test("Daily status follows day boundaries and completion")
    func dailyStatuses() {
        let yesterday = DayKey(rawValue: "2026-10-22")
        let today = DayKey(rawValue: "2026-10-23")
        let tomorrow = DayKey(rawValue: "2026-10-24")

        #expect(calculator.dailyStatus(day: yesterday, completed: false, now: now) == .missed)
        #expect(calculator.dailyStatus(day: today, completed: false, now: now) == .pendingToday)
        #expect(calculator.dailyStatus(day: tomorrow, completed: false, now: now) == .upcoming)
        #expect(calculator.dailyStatus(day: yesterday, completed: true, now: now) == .completed)
        #expect(calculator.dailyStatus(day: tomorrow, completed: true, now: now) == .completed)

        let completedItem = DailyItem(
            planDate: yesterday,
            sortIndex: 0,
            content: "已完成事项",
            plannedAt: TestDates.date(2026, 10, 22, hour: 18),
            actualAt: TestDates.date(2026, 10, 22, hour: 17),
            createdAt: now,
            updatedAt: now
        )
        #expect(calculator.dailyStatus(for: completedItem, now: now) == .completed)
    }

    @Test("Day summary status prioritizes unfinished work")
    func daySummaryStatus() {
        let missed = DaySummary(day: DayKey(rawValue: "2026-10-22"), total: 3, completed: 2)
        let today = DaySummary(day: DayKey(rawValue: "2026-10-23"), total: 2, completed: 1)
        let completed = DaySummary(day: DayKey(rawValue: "2026-10-23"), total: 2, completed: 2)
        let upcoming = DaySummary(day: DayKey(rawValue: "2026-10-25"), total: 1, completed: 0)
        let empty = DaySummary(day: DayKey(rawValue: "2026-10-25"), total: 0, completed: 0)

        #expect(calculator.dayStatus(for: missed, now: now) == .missed)
        #expect(calculator.dayStatus(for: today, now: now) == .pendingToday)
        #expect(calculator.dayStatus(for: completed, now: now) == .completed)
        #expect(calculator.dayStatus(for: upcoming, now: now) == .upcoming)
        #expect(calculator.dayStatus(for: empty, now: now) == nil)
    }

    @Test("Work status covers on-time, late, same-day and cross-day cases")
    func workStatuses() {
        let planned = TestDates.date(2026, 10, 20, hour: 18)

        #expect(
            calculator.workStatus(
                for: makeTask(plannedAt: planned, actualAt: TestDates.date(2026, 10, 20, hour: 17)),
                now: now
            ) == .completed
        )
        #expect(
            calculator.workStatus(
                for: makeTask(plannedAt: planned, actualAt: TestDates.date(2026, 10, 20, hour: 20)),
                now: now
            ) == .completedLate(days: 0)
        )
        #expect(
            calculator.workStatus(
                for: makeTask(plannedAt: planned, actualAt: TestDates.date(2026, 10, 22, hour: 9)),
                now: now
            ) == .completedLate(days: 2)
        )
        #expect(
            calculator.workStatus(
                for: makeTask(plannedAt: TestDates.date(2026, 10, 25, hour: 18)),
                now: now
            ) == .inProgress
        )
        #expect(
            calculator.workStatus(
                for: makeTask(plannedAt: TestDates.date(2026, 10, 23, hour: 9)),
                now: now
            ) == .overdue(days: 0)
        )
        #expect(
            calculator.workStatus(for: makeTask(plannedAt: planned), now: now) == .overdue(days: 3)
        )
    }

    @Test("Overdue day count respects calendar days across DST")
    func overdueAcrossDST() {
        let newYork = TestDates.calendar(in: "America/New_York")
        let dstCalculator = StatusCalculator(calendar: newYork)
        let planned = TestDates.date(2026, 3, 7, hour: 10, calendar: newYork)
        let reference = TestDates.date(2026, 3, 9, hour: 10, calendar: newYork)

        #expect(dstCalculator.overdueDayCount(from: planned, to: reference) == 2)
        #expect(dstCalculator.overdueDayCount(from: planned, to: planned) == 0)
        #expect(dstCalculator.overdueDayCount(from: reference, to: planned) == 0)
    }

    @Test("Day key and date round-trip in local calendar")
    func dayKeyRoundTrip() {
        let calendar = TestDates.defaultCalendar
        let date = TestDates.date(2026, 10, 23, hour: 23, calendar: calendar)
        let key = CalendarSupport.dayKey(for: date, calendar: calendar)

        #expect(key.rawValue == "2026-10-23")
        let reconstructed = CalendarSupport.date(for: key, calendar: calendar)
        #expect(reconstructed != nil)
        #expect(CalendarSupport.dayKey(for: reconstructed!, calendar: calendar) == key)
    }

    private func makeTask(plannedAt: Date, actualAt: Date? = nil) -> WorkTask {
        WorkTask(
            title: "测试任务",
            plannedAt: plannedAt,
            actualAt: actualAt,
            createdAt: now,
            updatedAt: now
        )
    }
}
