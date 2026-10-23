import Foundation
@testable import WorkLogCore

struct TestEnvironment: Sendable {
    let baseURL: URL
    let paths: DataPaths
    let store: WorkLogStore

    static func make(calendar: Calendar = TestDates.defaultCalendar) throws -> TestEnvironment {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkLogTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try DataPaths(
            rootURL: baseURL.appendingPathComponent("data", isDirectory: true),
            backupsURL: baseURL.appendingPathComponent("backups", isDirectory: true)
        )
        let store = try WorkLogStore(paths: paths, calendar: calendar)
        return TestEnvironment(baseURL: baseURL, paths: paths, store: store)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: baseURL)
    }
}

enum TestDates {
    static var defaultCalendar: Calendar {
        calendar(in: "Asia/Shanghai")
    }

    static func calendar(in timeZoneID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 12,
        minute: Int = 0,
        calendar: Calendar? = nil
    ) -> Date {
        let targetCalendar = calendar ?? defaultCalendar
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = targetCalendar.timeZone
        return targetCalendar.date(from: components)!
    }

    static func dayKey(for date: Date, calendar: Calendar? = nil) -> DayKey {
        CalendarSupport.dayKey(for: date, calendar: calendar ?? defaultCalendar)
    }
}
