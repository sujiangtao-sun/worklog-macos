import Foundation

public actor WorkLogStore {
    private let database: SQLiteConnection
    private let calendar: Calendar

    public init(paths: DataPaths, calendar: Calendar = .autoupdatingCurrent) throws {
        let connection = try SQLiteConnection(path: paths.databaseURL.path)
        try Migrations.migrate(connection)
        self.database = connection
        self.calendar = calendar
    }

    // MARK: - Daily items

    public func dailyItems(on day: DayKey) throws -> [DailyItem] {
        let statement = try database.prepare(
            """
            SELECT id, plan_date, sort_index, content, planned_at, actual_at,
                   difficulty, feedback, created_at, updated_at
            FROM daily_items
            WHERE plan_date = ?
            ORDER BY sort_index ASC, created_at ASC;
            """
        )
        try statement.bind(day.rawValue, at: 1)

        var items: [DailyItem] = []
        while try statement.step() {
            items.append(try decodeDailyItem(statement))
        }
        return items
    }

    public func daySummaries(from start: DayKey, through end: DayKey) throws -> [DaySummary] {
        guard start <= end else { return [] }

        let statement = try database.prepare(
            """
            SELECT plan_date,
                   COUNT(*),
                   COALESCE(SUM(CASE WHEN actual_at IS NOT NULL THEN 1 ELSE 0 END), 0)
            FROM daily_items
            WHERE plan_date >= ? AND plan_date <= ?
            GROUP BY plan_date
            ORDER BY plan_date ASC;
            """
        )
        try statement.bind(start.rawValue, at: 1)
        try statement.bind(end.rawValue, at: 2)

        var summaries: [DaySummary] = []
        while try statement.step() {
            guard let day = statement.string(at: 0) else {
                throw WorkLogDatabaseError.corruptedRow("日期分组数据缺失")
            }
            summaries.append(
                DaySummary(
                    day: DayKey(rawValue: day),
                    total: statement.int(at: 1),
                    completed: statement.int(at: 2)
                )
            )
        }
        return summaries
    }

    @discardableResult
    public func addDailyItem(
        planDate: DayKey,
        content: String,
        plannedAt: Date,
        difficulty: String = "",
        feedback: String = "",
        now: Date = Date()
    ) throws -> DailyItem {
        try validateDaily(planDate: planDate, content: content, plannedAt: plannedAt)

        let sortIndex = try nextSortIndex(for: planDate)
        let item = DailyItem(
            planDate: planDate,
            sortIndex: sortIndex,
            content: content,
            plannedAt: plannedAt,
            difficulty: difficulty,
            feedback: feedback,
            createdAt: now,
            updatedAt: now
        )

        let statement = try database.prepare(
            """
            INSERT INTO daily_items
                (id, plan_date, sort_index, content, planned_at, actual_at,
                 difficulty, feedback, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        )
        try statement.bind(item.id.uuidString, at: 1)
        try statement.bind(item.planDate.rawValue, at: 2)
        try statement.bind(item.sortIndex, at: 3)
        try statement.bind(item.content, at: 4)
        try statement.bind(milliseconds(from: item.plannedAt), at: 5)
        try bindOptionalDate(item.actualAt, to: statement, at: 6)
        try statement.bind(item.difficulty, at: 7)
        try statement.bind(item.feedback, at: 8)
        try statement.bind(milliseconds(from: item.createdAt), at: 9)
        try statement.bind(milliseconds(from: item.updatedAt), at: 10)
        _ = try statement.step()

        return item
    }

    public func updateDailyItem(_ item: DailyItem, now: Date = Date()) throws {
        try validateDaily(planDate: item.planDate, content: item.content, plannedAt: item.plannedAt)

        let previousPlanDate = try storedPlanDate(for: item.id)
        var sortIndex = item.sortIndex
        if let previousPlanDate, previousPlanDate != item.planDate {
            sortIndex = try nextSortIndex(for: item.planDate)
        }

        let statement = try database.prepare(
            """
            UPDATE daily_items
            SET plan_date = ?, sort_index = ?, content = ?, planned_at = ?,
                actual_at = ?, difficulty = ?, feedback = ?, updated_at = ?
            WHERE id = ?;
            """
        )
        try statement.bind(item.planDate.rawValue, at: 1)
        try statement.bind(sortIndex, at: 2)
        try statement.bind(item.content, at: 3)
        try statement.bind(milliseconds(from: item.plannedAt), at: 4)
        try bindOptionalDate(item.actualAt, to: statement, at: 5)
        try statement.bind(item.difficulty, at: 6)
        try statement.bind(item.feedback, at: 7)
        try statement.bind(milliseconds(from: now), at: 8)
        try statement.bind(item.id.uuidString, at: 9)
        _ = try statement.step()

        guard database.changes > 0 else {
            throw WorkLogDatabaseError.notFound("每日事项")
        }
    }

    public func setDailyItemActual(id: UUID, actualAt: Date?, now: Date = Date()) throws {
        let statement = try database.prepare(
            "UPDATE daily_items SET actual_at = ?, updated_at = ? WHERE id = ?;"
        )
        try bindOptionalDate(actualAt, to: statement, at: 1)
        try statement.bind(milliseconds(from: now), at: 2)
        try statement.bind(id.uuidString, at: 3)
        _ = try statement.step()

        guard database.changes > 0 else {
            throw WorkLogDatabaseError.notFound("每日事项")
        }
    }

    public func deleteDailyItem(id: UUID) throws {
        let statement = try database.prepare("DELETE FROM daily_items WHERE id = ?;")
        try statement.bind(id.uuidString, at: 1)
        _ = try statement.step()

        guard database.changes > 0 else {
            throw WorkLogDatabaseError.notFound("每日事项")
        }
    }

    // MARK: - Work tasks

    public func workTasks() throws -> [WorkTask] {
        let statement = try database.prepare(
            """
            SELECT id, title, content_path, content_plain, planned_at, actual_at,
                   created_at, updated_at
            FROM work_tasks
            ORDER BY (actual_at IS NOT NULL) ASC,
                     CASE WHEN actual_at IS NULL THEN planned_at END ASC,
                     actual_at DESC,
                     created_at ASC;
            """
        )

        var tasks: [WorkTask] = []
        while try statement.step() {
            tasks.append(try decodeWorkTask(statement))
        }
        return tasks
    }

    public func workTask(id: UUID) throws -> WorkTask? {
        let statement = try database.prepare(
            """
            SELECT id, title, content_path, content_plain, planned_at, actual_at,
                   created_at, updated_at
            FROM work_tasks
            WHERE id = ?;
            """
        )
        try statement.bind(id.uuidString, at: 1)
        guard try statement.step() else { return nil }
        return try decodeWorkTask(statement)
    }

    @discardableResult
    public func addWorkTask(
        id: UUID = UUID(),
        title: String,
        contentPath: String?,
        contentPlain: String,
        plannedAt: Date,
        now: Date = Date()
    ) throws -> WorkTask {
        let normalizedTitle = try validateWorkTitle(title)
        try validateRichContent(path: contentPath, plain: contentPlain)

        let task = WorkTask(
            id: id,
            title: normalizedTitle,
            contentPath: contentPath,
            contentPlain: contentPlain,
            plannedAt: plannedAt,
            createdAt: now,
            updatedAt: now
        )

        let statement = try database.prepare(
            """
            INSERT INTO work_tasks
                (id, title, content_path, content_plain, planned_at, actual_at,
                 created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
        )
        try statement.bind(task.id.uuidString, at: 1)
        try statement.bind(task.title, at: 2)
        try statement.bind(task.contentPath, at: 3)
        try statement.bind(task.contentPlain, at: 4)
        try statement.bind(milliseconds(from: task.plannedAt), at: 5)
        try bindOptionalDate(task.actualAt, to: statement, at: 6)
        try statement.bind(milliseconds(from: task.createdAt), at: 7)
        try statement.bind(milliseconds(from: task.updatedAt), at: 8)
        _ = try statement.step()

        return task
    }

    public func updateWorkTask(_ task: WorkTask, now: Date = Date()) throws {
        let normalizedTitle = try validateWorkTitle(task.title)
        try validateRichContent(path: task.contentPath, plain: task.contentPlain)

        let statement = try database.prepare(
            """
            UPDATE work_tasks
            SET title = ?, content_path = ?, content_plain = ?, planned_at = ?,
                actual_at = ?, updated_at = ?
            WHERE id = ?;
            """
        )
        try statement.bind(normalizedTitle, at: 1)
        try statement.bind(task.contentPath, at: 2)
        try statement.bind(task.contentPlain, at: 3)
        try statement.bind(milliseconds(from: task.plannedAt), at: 4)
        try bindOptionalDate(task.actualAt, to: statement, at: 5)
        try statement.bind(milliseconds(from: now), at: 6)
        try statement.bind(task.id.uuidString, at: 7)
        _ = try statement.step()

        guard database.changes > 0 else {
            throw WorkLogDatabaseError.notFound("工作项")
        }
    }

    public func setWorkTaskActual(id: UUID, actualAt: Date?, now: Date = Date()) throws {
        let statement = try database.prepare(
            "UPDATE work_tasks SET actual_at = ?, updated_at = ? WHERE id = ?;"
        )
        try bindOptionalDate(actualAt, to: statement, at: 1)
        try statement.bind(milliseconds(from: now), at: 2)
        try statement.bind(id.uuidString, at: 3)
        _ = try statement.step()

        guard database.changes > 0 else {
            throw WorkLogDatabaseError.notFound("工作项")
        }
    }

    public func deleteWorkTask(id: UUID) throws -> [String] {
        let select = try database.prepare(
            """
            SELECT content_path FROM work_tasks
            WHERE id = ? AND content_path IS NOT NULL
            UNION ALL
            SELECT content_path FROM work_progress
            WHERE task_id = ? AND content_path IS NOT NULL;
            """
        )
        try select.bind(id.uuidString, at: 1)
        try select.bind(id.uuidString, at: 2)

        var paths: [String] = []
        while try select.step() {
            if let path = select.string(at: 0) {
                paths.append(path)
            }
        }

        let delete = try database.prepare("DELETE FROM work_tasks WHERE id = ?;")
        try delete.bind(id.uuidString, at: 1)
        _ = try delete.step()

        guard database.changes > 0 else {
            throw WorkLogDatabaseError.notFound("工作项")
        }
        return paths
    }

    // MARK: - Progress

    public func progressEntries(for taskID: UUID) throws -> [WorkProgress] {
        let statement = try database.prepare(
            """
            SELECT id, task_id, content_path, content_plain, created_at, updated_at
            FROM work_progress
            WHERE task_id = ?
            ORDER BY created_at DESC, id DESC;
            """
        )
        try statement.bind(taskID.uuidString, at: 1)

        var entries: [WorkProgress] = []
        while try statement.step() {
            entries.append(try decodeProgress(statement))
        }
        return entries
    }

    @discardableResult
    public func addProgress(
        id: UUID = UUID(),
        taskID: UUID,
        contentPath: String?,
        contentPlain: String,
        now: Date = Date()
    ) throws -> WorkProgress {
        try validateProgressContent(path: contentPath, plain: contentPlain)

        guard try workTask(id: taskID) != nil else {
            throw WorkLogDatabaseError.notFound("工作项")
        }

        let progress = WorkProgress(
            id: id,
            taskID: taskID,
            contentPath: contentPath,
            contentPlain: contentPlain,
            createdAt: now,
            updatedAt: now
        )

        let statement = try database.prepare(
            """
            INSERT INTO work_progress
                (id, task_id, content_path, content_plain, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?);
            """
        )
        try statement.bind(progress.id.uuidString, at: 1)
        try statement.bind(progress.taskID.uuidString, at: 2)
        try statement.bind(progress.contentPath, at: 3)
        try statement.bind(progress.contentPlain, at: 4)
        try statement.bind(milliseconds(from: progress.createdAt), at: 5)
        try statement.bind(milliseconds(from: progress.updatedAt), at: 6)
        _ = try statement.step()

        return progress
    }

    public func updateProgress(_ progress: WorkProgress, now: Date = Date()) throws {
        try validateProgressContent(path: progress.contentPath, plain: progress.contentPlain)

        let statement = try database.prepare(
            """
            UPDATE work_progress
            SET content_path = ?, content_plain = ?, updated_at = ?
            WHERE id = ?;
            """
        )
        try statement.bind(progress.contentPath, at: 1)
        try statement.bind(progress.contentPlain, at: 2)
        try statement.bind(milliseconds(from: now), at: 3)
        try statement.bind(progress.id.uuidString, at: 4)
        _ = try statement.step()

        guard database.changes > 0 else {
            throw WorkLogDatabaseError.notFound("进展记录")
        }
    }

    public func deleteProgress(id: UUID) throws -> String? {
        let select = try database.prepare(
            "SELECT content_path FROM work_progress WHERE id = ?;"
        )
        try select.bind(id.uuidString, at: 1)
        guard try select.step() else {
            throw WorkLogDatabaseError.notFound("进展记录")
        }
        let path = select.string(at: 0)

        let delete = try database.prepare("DELETE FROM work_progress WHERE id = ?;")
        try delete.bind(id.uuidString, at: 1)
        _ = try delete.step()

        guard database.changes > 0 else {
            throw WorkLogDatabaseError.notFound("进展记录")
        }
        return path
    }

    // MARK: - Maintenance

    public func referencedContentPaths() throws -> Set<String> {
        let statement = try database.prepare(
            """
            SELECT content_path FROM work_tasks WHERE content_path IS NOT NULL
            UNION
            SELECT content_path FROM work_progress WHERE content_path IS NOT NULL;
            """
        )

        var paths = Set<String>()
        while try statement.step() {
            if let path = statement.string(at: 0) {
                paths.insert(path)
            }
        }
        return paths
    }

    public func snapshotDatabase(to destinationURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try database.backup(to: destinationURL)
    }

    // MARK: - Validation and decoding

    private func validateDaily(planDate: DayKey, content: String, plannedAt: Date) throws {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkLogDatabaseError.validation("事项内容不能为空")
        }
        guard CalendarSupport.dayKey(for: plannedAt, calendar: calendar) == planDate else {
            throw WorkLogDatabaseError.validation("计划完成时间必须落在所选日期内")
        }
    }

    private func validateWorkTitle(_ title: String) throws -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw WorkLogDatabaseError.validation("工作内容不能为空")
        }
        return normalized
    }

    private func validateProgressContent(path: String?, plain: String) throws {
        let hasText = !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard path != nil || hasText else {
            throw WorkLogDatabaseError.validation("进展内容不能为空")
        }
        if let path, !path.hasPrefix("attachments/") {
            throw WorkLogDatabaseError.validation("附件路径不合法")
        }
    }

    private func validateRichContent(path: String?, plain: String) throws {
        if path == nil, !plain.isEmpty {
            throw WorkLogDatabaseError.validation("富文本附件路径缺失")
        }
        if let path, !path.hasPrefix("attachments/") {
            throw WorkLogDatabaseError.validation("附件路径不合法")
        }
    }

    private func nextSortIndex(for day: DayKey) throws -> Int {
        let statement = try database.prepare(
            "SELECT COALESCE(MAX(sort_index), -1) + 1 FROM daily_items WHERE plan_date = ?;"
        )
        try statement.bind(day.rawValue, at: 1)
        guard try statement.step() else {
            throw WorkLogDatabaseError.corruptedRow("无法计算每日事项排序")
        }
        return statement.int(at: 0)
    }

    private func storedPlanDate(for id: UUID) throws -> DayKey? {
        let statement = try database.prepare(
            "SELECT plan_date FROM daily_items WHERE id = ?;"
        )
        try statement.bind(id.uuidString, at: 1)
        guard try statement.step(), let rawValue = statement.string(at: 0) else {
            return nil
        }
        return DayKey(rawValue: rawValue)
    }

    private func decodeDailyItem(_ statement: SQLiteStatement) throws -> DailyItem {
        let id = try uuidColumn(statement, at: 0)
        guard let planDate = statement.string(at: 1) else {
            throw WorkLogDatabaseError.corruptedRow("每日事项日期缺失")
        }

        return DailyItem(
            id: id,
            planDate: DayKey(rawValue: planDate),
            sortIndex: statement.int(at: 2),
            content: statement.string(at: 3) ?? "",
            plannedAt: date(fromMilliseconds: statement.int64(at: 4)),
            actualAt: optionalDate(statement, at: 5),
            difficulty: statement.string(at: 6) ?? "",
            feedback: statement.string(at: 7) ?? "",
            createdAt: date(fromMilliseconds: statement.int64(at: 8)),
            updatedAt: date(fromMilliseconds: statement.int64(at: 9))
        )
    }

    private func decodeWorkTask(_ statement: SQLiteStatement) throws -> WorkTask {
        WorkTask(
            id: try uuidColumn(statement, at: 0),
            title: statement.string(at: 1) ?? "",
            contentPath: statement.string(at: 2),
            contentPlain: statement.string(at: 3) ?? "",
            plannedAt: date(fromMilliseconds: statement.int64(at: 4)),
            actualAt: optionalDate(statement, at: 5),
            createdAt: date(fromMilliseconds: statement.int64(at: 6)),
            updatedAt: date(fromMilliseconds: statement.int64(at: 7))
        )
    }

    private func decodeProgress(_ statement: SQLiteStatement) throws -> WorkProgress {
        WorkProgress(
            id: try uuidColumn(statement, at: 0),
            taskID: try uuidColumn(statement, at: 1),
            contentPath: statement.string(at: 2),
            contentPlain: statement.string(at: 3) ?? "",
            createdAt: date(fromMilliseconds: statement.int64(at: 4)),
            updatedAt: date(fromMilliseconds: statement.int64(at: 5))
        )
    }

    private func uuidColumn(_ statement: SQLiteStatement, at index: Int32) throws -> UUID {
        guard let raw = statement.string(at: index), let id = UUID(uuidString: raw) else {
            throw WorkLogDatabaseError.corruptedRow("无法解析记录标识")
        }
        return id
    }

    private func bindOptionalDate(
        _ date: Date?,
        to statement: SQLiteStatement,
        at index: Int32
    ) throws {
        if let date {
            try statement.bind(milliseconds(from: date), at: index)
        } else {
            try statement.bindNull(at: index)
        }
    }

    private func optionalDate(_ statement: SQLiteStatement, at index: Int32) -> Date? {
        statement.isNull(at: index) ? nil : date(fromMilliseconds: statement.int64(at: index))
    }

    private func milliseconds(from date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private func date(fromMilliseconds value: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(value) / 1_000)
    }
}
