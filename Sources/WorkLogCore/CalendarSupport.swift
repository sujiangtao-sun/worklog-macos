import Foundation

public enum CalendarSupport {
    public static func dayKey(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> DayKey {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return DayKey(rawValue: "\(year)-\(padded(month))-\(padded(day))")
    }

    public static func date(for key: DayKey, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        let parts = key.rawValue.split(separator: "-", omittingEmptySubsequences: true)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    public static func date(
        on day: DayKey,
        hour: Int,
        minute: Int,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        guard let dayStart = date(for: day, calendar: calendar) else { return nil }
        let baseComponents = calendar.dateComponents([.year, .month, .day], from: dayStart)
        var components = DateComponents()
        components.year = baseComponents.year
        components.month = baseComponents.month
        components.day = baseComponents.day
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.timeZone = calendar.timeZone
        return calendar.date(from: components)
    }

    public static func dayKey(
        byAddingDays days: Int,
        to date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> DayKey {
        let shifted = calendar.date(byAdding: .day, value: days, to: date) ?? date
        return dayKey(for: shifted, calendar: calendar)
    }

    public static func startOfDay(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.startOfDay(for: date)
    }

    public static func monthDayRange(
        year: Int,
        month: Int,
        calendar: Calendar = .autoupdatingCurrent
    ) -> (first: DayKey, last: DayKey)? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        components.timeZone = calendar.timeZone

        guard let firstDate = calendar.date(from: components),
              let dayRange = calendar.range(of: .day, in: .month, for: firstDate),
              let lastDate = calendar.date(byAdding: .day, value: dayRange.count - 1, to: firstDate) else {
            return nil
        }
        return (dayKey(for: firstDate, calendar: calendar), dayKey(for: lastDate, calendar: calendar))
    }

    private static func padded(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
