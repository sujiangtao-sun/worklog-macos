import Foundation
import Testing
@testable import WorkLogCore

@Suite("WorkLog store")
struct WorkLogStoreTests {
    @Test("Daily items support CRUD, ordering, summaries and persistence")
    func dailyItemLifecycle() async throws {
        let env = try TestEnvironment.make()
        defer { env.cleanup() }

        let calendar = TestDates.defaultCalendar
        let day = TestDates.dayKey(for: TestDates.date(2026, 10, 23, hour: 12, calendar: calendar), calendar: calendar)
        let evening = TestDates.date(2026, 10, 23, hour: 18, calendar: calendar)
        let morning = TestDates.date(2026, 10, 23, hour: 9, calendar: calendar)
        let baseNow = TestDates.date(2026, 10, 23, hour: 8, calendar: calendar)

        let first = try await env.store.addDailyItem(
            planDate: day,
            content: "写周报",
            plannedAt: evening,
            now: baseNow
        )
        let second = try await env.store.addDailyItem(
            planDate: day,
            content: "审阅方案",
            plannedAt: morning,
            now: baseNow.addingTimeInterval(60)
        )

        var items = try await env.store.dailyItems(on: day)
        #expect(items.count == 2)
        #expect(items.map(\.id) == [first.id, second.id])
        #expect(items[0].sortIndex == 0)
        #expect(items[1].sortIndex == 1)

        let completedAt = TestDates.date(2026, 10, 23, hour: 17, calendar: calendar)
        try await env.store.setDailyItemActual(id: first.id, actualAt: completedAt, now: completedAt)

        items = try await env.store.dailyItems(on: day)
        #expect(items[0].actualAt != nil)
        #expect(items[0].isCompleted)

        var edited = items[1]
        edited.content = "审阅方案\n补充：接口与异常流程"
        edited.difficulty = "依赖外部评审时间"
        edited.feedback = "已完成初稿"
        edited.actualAt = TestDates.date(2026, 10, 23, hour: 19, calendar: calendar)
        try await env.store.updateDailyItem(edited, now: edited.actualAt!)

        let summaries = try await env.store.daySummaries(from: day, through: day)
        #expect(summaries.count == 1)
        #expect(summaries.first?.total == 2)
        #expect(summaries.first?.completed == 2)

        do {
            _ = try await env.store.addDailyItem(
                planDate: day,
                content: "   ",
                plannedAt: evening
            )
            Issue.record("Empty daily content should be rejected")
        } catch is WorkLogDatabaseError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            _ = try await env.store.addDailyItem(
                planDate: day,
                content: "跨日事项",
                plannedAt: TestDates.date(2026, 10, 24, hour: 9, calendar: calendar)
            )
            Issue.record("Plan time on a different day should be rejected")
        } catch is WorkLogDatabaseError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        try await env.store.deleteDailyItem(id: second.id)
        items = try await env.store.dailyItems(on: day)
        #expect(items.count == 1)

        let reopened = try WorkLogStore(paths: env.paths, calendar: calendar)
        let reopenedItems = try await reopened.dailyItems(on: day)
        #expect(reopenedItems.count == 1)
        #expect(reopenedItems[0].content == "写周报")
    }

    @Test("Moving a daily item to another day appends it to that day")
    func moveDailyItemBetweenDays() async throws {
        let env = try TestEnvironment.make()
        defer { env.cleanup() }

        let calendar = TestDates.defaultCalendar
        let dayOne = TestDates.dayKey(
            for: TestDates.date(2026, 10, 23, hour: 12, calendar: calendar),
            calendar: calendar
        )
        let dayTwo = TestDates.dayKey(
            for: TestDates.date(2026, 10, 24, hour: 12, calendar: calendar),
            calendar: calendar
        )
        let baseNow = TestDates.date(2026, 10, 23, hour: 8, calendar: calendar)

        let existing = try await env.store.addDailyItem(
            planDate: dayTwo,
            content: "目标日已有事项",
            plannedAt: TestDates.date(2026, 10, 24, hour: 9, calendar: calendar),
            now: baseNow
        )
        let item = try await env.store.addDailyItem(
            planDate: dayOne,
            content: "需要移动的事项",
            plannedAt: TestDates.date(2026, 10, 23, hour: 18, calendar: calendar),
            now: baseNow.addingTimeInterval(60)
        )

        var moved = item
        moved.planDate = dayTwo
        moved.plannedAt = TestDates.date(2026, 10, 24, hour: 18, calendar: calendar)
        try await env.store.updateDailyItem(moved, now: baseNow.addingTimeInterval(120))

        let sourceItems = try await env.store.dailyItems(on: dayOne)
        let targetItems = try await env.store.dailyItems(on: dayTwo)

        #expect(sourceItems.isEmpty)
        #expect(targetItems.count == 2)
        #expect(targetItems.first?.id == existing.id)
        #expect(targetItems.last?.id == item.id)
    }

    @Test("Work tasks keep deterministic order and delete progress in cascade")
    func workLifecycle() async throws {
        let env = try TestEnvironment.make()
        defer { env.cleanup() }

        let calendar = TestDates.defaultCalendar
        let baseNow = TestDates.date(2026, 10, 23, hour: 9, calendar: calendar)

        let taskA = try await env.store.addWorkTask(
            title: "方案评审",
            contentPath: nil,
            contentPlain: "",
            plannedAt: TestDates.date(2026, 10, 25, hour: 18, calendar: calendar),
            now: baseNow
        )
        let taskB = try await env.store.addWorkTask(
            title: "接口联调",
            contentPath: nil,
            contentPlain: "",
            plannedAt: TestDates.date(2026, 10, 24, hour: 18, calendar: calendar),
            now: baseNow.addingTimeInterval(60)
        )

        var tasks = try await env.store.workTasks()
        #expect(tasks.map(\.id) == [taskB.id, taskA.id])

        let progressPath1 = DataPaths.attachmentRelativePath(for: UUID())
        let progressPath2 = DataPaths.attachmentRelativePath(for: UUID())

        let progress1 = try await env.store.addProgress(
            taskID: taskA.id,
            contentPath: progressPath1,
            contentPlain: "完成资料收集",
            now: baseNow.addingTimeInterval(120)
        )
        let progress2 = try await env.store.addProgress(
            taskID: taskA.id,
            contentPath: progressPath2,
            contentPlain: "已发出评审邀请",
            now: baseNow.addingTimeInterval(180)
        )

        var progress = try await env.store.progressEntries(for: taskA.id)
        #expect(progress.map(\.id) == [progress2.id, progress1.id])

        var editedProgress = progress[0]
        editedProgress.contentPlain = "已发出评审邀请，等待反馈"
        try await env.store.updateProgress(editedProgress, now: baseNow.addingTimeInterval(240))

        progress = try await env.store.progressEntries(for: taskA.id)
        #expect(progress[0].contentPlain == "已发出评审邀请，等待反馈")

        var taskWithContent = taskB
        let taskPath = DataPaths.attachmentRelativePath(for: taskB.id)
        taskWithContent.contentPath = taskPath
        taskWithContent.contentPlain = "接口联调说明"
        try await env.store.updateWorkTask(taskWithContent, now: baseNow.addingTimeInterval(300))

        let completion = TestDates.date(2026, 10, 26, hour: 10, calendar: calendar)
        try await env.store.setWorkTaskActual(id: taskA.id, actualAt: completion, now: completion)

        tasks = try await env.store.workTasks()
        #expect(tasks.first?.id == taskB.id)
        #expect(tasks.last?.id == taskA.id)
        #expect(tasks.last?.actualAt == completion)

        let referencedBefore = try await env.store.referencedContentPaths()
        #expect(referencedBefore == Set([progressPath1, progressPath2, taskPath]))

        let removedTaskAPaths = try await env.store.deleteWorkTask(id: taskA.id)
        #expect(Set(removedTaskAPaths) == Set([progressPath1, progressPath2]))
        let remainingProgress = try await env.store.progressEntries(for: taskA.id)
        #expect(remainingProgress.isEmpty)

        let removedTaskBPaths = try await env.store.deleteWorkTask(id: taskB.id)
        #expect(removedTaskBPaths == [taskPath])

        let referencedAfter = try await env.store.referencedContentPaths()
        #expect(referencedAfter.isEmpty)
        let lookup = try await env.store.workTask(id: taskA.id)
        #expect(lookup == nil)
    }

    @Test("Validation rejects empty titles and inconsistent rich content")
    func validation() async throws {
        let env = try TestEnvironment.make()
        defer { env.cleanup() }

        let calendar = TestDates.defaultCalendar
        let now = TestDates.date(2026, 10, 23, hour: 10, calendar: calendar)

        do {
            _ = try await env.store.addWorkTask(
                title: "   ",
                contentPath: nil,
                contentPlain: "",
                plannedAt: TestDates.date(2026, 10, 25, hour: 18, calendar: calendar),
                now: now
            )
            Issue.record("Empty work title should be rejected")
        } catch is WorkLogDatabaseError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            _ = try await env.store.addWorkTask(
                title: "内容不一致",
                contentPath: nil,
                contentPlain: "有文本但没有富文本路径",
                plannedAt: TestDates.date(2026, 10, 25, hour: 18, calendar: calendar),
                now: now
            )
            Issue.record("Plain text without rich text path should be rejected")
        } catch is WorkLogDatabaseError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let task = try await env.store.addWorkTask(
            title: "进展校验",
            contentPath: nil,
            contentPlain: "",
            plannedAt: TestDates.date(2026, 10, 25, hour: 18, calendar: calendar),
            now: now
        )

        do {
            _ = try await env.store.addProgress(
                taskID: task.id,
                contentPath: nil,
                contentPlain: "   ",
                now: now
            )
            Issue.record("Empty progress should be rejected")
        } catch is WorkLogDatabaseError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
