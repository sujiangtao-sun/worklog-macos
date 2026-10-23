import Foundation

public struct DayKey: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct DailyItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var planDate: DayKey
    public var sortIndex: Int
    public var content: String
    public var plannedAt: Date
    public var actualAt: Date?
    public var difficulty: String
    public var feedback: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        planDate: DayKey,
        sortIndex: Int,
        content: String,
        plannedAt: Date,
        actualAt: Date? = nil,
        difficulty: String = "",
        feedback: String = "",
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.planDate = planDate
        self.sortIndex = sortIndex
        self.content = content
        self.plannedAt = plannedAt
        self.actualAt = actualAt
        self.difficulty = difficulty
        self.feedback = feedback
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isCompleted: Bool { actualAt != nil }
}

public struct WorkTask: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var contentPath: String?
    public var contentPlain: String
    public var plannedAt: Date
    public var actualAt: Date?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        contentPath: String? = nil,
        contentPlain: String = "",
        plannedAt: Date,
        actualAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.contentPath = contentPath
        self.contentPlain = contentPlain
        self.plannedAt = plannedAt
        self.actualAt = actualAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isCompleted: Bool { actualAt != nil }
}

public struct WorkProgress: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let taskID: UUID
    public var contentPath: String?
    public var contentPlain: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        taskID: UUID,
        contentPath: String? = nil,
        contentPlain: String = "",
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.taskID = taskID
        self.contentPath = contentPath
        self.contentPlain = contentPlain
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct DaySummary: Equatable, Sendable {
    public let day: DayKey
    public let total: Int
    public let completed: Int

    public init(day: DayKey, total: Int, completed: Int) {
        self.day = day
        self.total = total
        self.completed = completed
    }

    public var incomplete: Int { total - completed }
    public var isAllCompleted: Bool { total > 0 && completed == total }
}

public enum DailyStatus: Equatable, Sendable {
    case completed
    case missed
    case pendingToday
    case upcoming
}

public enum WorkStatus: Equatable, Sendable {
    case completed
    case completedLate(days: Int)
    case inProgress
    case overdue(days: Int)

    public var isCompleted: Bool {
        switch self {
        case .completed, .completedLate:
            true
        case .inProgress, .overdue:
            false
        }
    }

    public var isOverdue: Bool {
        switch self {
        case .overdue:
            true
        case .completed, .completedLate, .inProgress:
            false
        }
    }

    public var overdueDays: Int? {
        switch self {
        case .completedLate(let days), .overdue(let days):
            days
        case .completed, .inProgress:
            nil
        }
    }
}
