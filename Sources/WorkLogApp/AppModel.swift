import AppKit
import Foundation
import Observation
import WorkLogCore
import os

extension Notification.Name {
    static let workLogCreateItem = Notification.Name("WorkLog.createItem")
    static let workLogGoToday = Notification.Name("WorkLog.goToday")
}

@MainActor
@Observable
final class AppModel {
    enum Section: String, CaseIterable, Identifiable, Hashable {
        case calendar
        case work

        var id: String { rawValue }

        var title: String {
            switch self {
            case .calendar: "日历待办"
            case .work: "工作跟踪"
            }
        }

        var systemImage: String {
            switch self {
            case .calendar: "calendar"
            case .work: "list.bullet.clipboard"
            }
        }
    }

    enum CalendarLevel: Equatable {
        case months
        case days
    }

    let paths: DataPaths
    let store: WorkLogStore
    let richTextStore: RichTextStore
    let backupService: BackupService

    private static let selectedSectionStorageKey = "ui.selectedSection"
    private static let calendarPanelStorageKey = "ui.calendarPanelVisible"

    private let statusCalculator: StatusCalculator
    private let logger = Logger(subsystem: "local.worklog.app", category: "AppModel")
    private var clockTask: Task<Void, Never>?
    private var lastClockDay: DayKey
    private var didBootstrap = false

    var selectedSection: Section = .calendar
    var isCalendarPanelVisible = true
    var now: Date
    var selectedDay: DayKey
    var calendarYear: Int
    var calendarMonth: Int
    var calendarLevel: CalendarLevel = .days
    var monthSummaries: [DayKey: DaySummary] = [:]
    var dailyItems: [DailyItem] = []
    var workTasks: [WorkTask] = []
    var selectedWorkTaskID: UUID?
    var progressEntries: [WorkProgress] = []
    var errorMessage: String?
    var isBackingUp = false
    var lastBackupDate: Date?
    var backupStatusMessage: String?

    init() throws {
        let paths = try DataPaths()
        self.paths = paths
        self.store = try WorkLogStore(paths: paths)
        self.richTextStore = RichTextStore(paths: paths)
        self.backupService = BackupService(paths: paths)
        self.statusCalculator = StatusCalculator()

        let current = Date()
        let todayKey = CalendarSupport.dayKey(for: current)
        let components = Calendar.autoupdatingCurrent.dateComponents([.year, .month], from: current)

        self.now = current
        self.selectedDay = todayKey
        self.lastClockDay = todayKey
        self.calendarYear = components.year ?? 2026
        self.calendarMonth = components.month ?? 1

        let savedSection = UserDefaults.standard
            .string(forKey: Self.selectedSectionStorageKey)
            .flatMap(Section.init(rawValue:)) ?? .calendar
        self.selectedSection = savedSection

        if let savedPanelVisibility = UserDefaults.standard
            .object(forKey: Self.calendarPanelStorageKey) as? Bool {
            self.isCalendarPanelVisible = savedPanelVisibility
        }
    }

    func selectSection(_ section: Section) {
        selectedSection = section
        UserDefaults.standard.set(section.rawValue, forKey: Self.selectedSectionStorageKey)
    }

    func toggleCalendarPanel() {
        isCalendarPanelVisible.toggle()
        UserDefaults.standard.set(
            isCalendarPanelVisible,
            forKey: Self.calendarPanelStorageKey
        )
    }

    var todayKey: DayKey {
        CalendarSupport.dayKey(for: now)
    }

    var selectedWorkTask: WorkTask? {
        guard let selectedWorkTaskID else { return nil }
        return workTasks.first { $0.id == selectedWorkTaskID }
    }

    var selectedDayIsToday: Bool {
        selectedDay == todayKey
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        now = Date()
        lastClockDay = todayKey
        await reloadSummaries()
        await reloadDaily()
        await reloadWork()
        await cleanupOrphanAttachments()
        lastBackupDate = backupService.lastBackupDate()
        await performDailyBackupIfNeeded()
        startClock()
    }

    func handleActivation() async {
        guard didBootstrap else { return }
        now = Date()
        lastClockDay = todayKey
        await reloadSummaries()
        await reloadDaily()
        await reloadWork()
        await performDailyBackupIfNeeded()
    }

    private func startClock() {
        guard clockTask == nil else { return }
        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.now = Date()
                let currentDay = self.todayKey
                if currentDay != self.lastClockDay {
                    self.lastClockDay = currentDay
                    await self.performDailyBackupIfNeeded()
                }
            }
        }
    }

    // MARK: - Loading

    func reloadSummaries() async {
        guard let range = CalendarSupport.monthDayRange(year: calendarYear, month: calendarMonth) else {
            monthSummaries = [:]
            return
        }

        do {
            let summaries = try await store.daySummaries(from: range.first, through: range.last)
            monthSummaries = Dictionary(uniqueKeysWithValues: summaries.map { ($0.day, $0) })
        } catch {
            present(error)
        }
    }

    func reloadDaily() async {
        do {
            dailyItems = try await store.dailyItems(on: selectedDay)
        } catch {
            present(error)
        }
    }

    func reloadWork() async {
        do {
            let tasks = try await store.workTasks()
            workTasks = tasks

            if let selectedWorkTaskID, !tasks.contains(where: { $0.id == selectedWorkTaskID }) {
                self.selectedWorkTaskID = tasks.first?.id
            } else if selectedWorkTaskID == nil {
                selectedWorkTaskID = tasks.first?.id
            }

            await reloadProgress()
        } catch {
            present(error)
        }
    }

    func reloadProgress() async {
        guard let selectedWorkTaskID else {
            progressEntries = []
            return
        }

        do {
            progressEntries = try await store.progressEntries(for: selectedWorkTaskID)
        } catch {
            present(error)
        }
    }

    // MARK: - Calendar navigation

    func selectDay(_ day: DayKey) async {
        selectedDay = day
        await reloadDaily()
    }

    func showMonthsOverview() {
        calendarLevel = .months
    }

    func setOverviewYear(_ year: Int) {
        guard calendarLevel == .months else { return }
        calendarYear = year
    }

    func showMonth(year: Int, month: Int) async {
        guard (1...12).contains(month) else { return }

        calendarYear = year
        calendarMonth = month
        calendarLevel = .days

        if !isDay(selectedDay, inYear: year, month: month) {
            if isDay(todayKey, inYear: year, month: month) {
                selectedDay = todayKey
            } else if let range = CalendarSupport.monthDayRange(year: year, month: month) {
                selectedDay = range.first
            }
        }

        await reloadSummaries()
        await reloadDaily()
    }

    func showPreviousMonth() async {
        guard let target = shiftedMonth(by: -1) else { return }
        await showMonth(year: target.year, month: target.month)
    }

    func showNextMonth() async {
        guard let target = shiftedMonth(by: 1) else { return }
        await showMonth(year: target.year, month: target.month)
    }

    func goToToday() async {
        now = Date()
        selectSection(.calendar)
        calendarLevel = .days
        selectedDay = todayKey

        let components = Calendar.autoupdatingCurrent.dateComponents([.year, .month], from: now)
        calendarYear = components.year ?? calendarYear
        calendarMonth = components.month ?? calendarMonth

        await reloadSummaries()
        await reloadDaily()
    }

    private func shiftedMonth(by offset: Int) -> (year: Int, month: Int)? {
        let calendar = Calendar.autoupdatingCurrent
        var components = DateComponents()
        components.year = calendarYear
        components.month = calendarMonth
        components.day = 1
        components.timeZone = calendar.timeZone

        guard let firstDay = calendar.date(from: components),
              let shifted = calendar.date(byAdding: .month, value: offset, to: firstDay) else {
            return nil
        }

        let result = calendar.dateComponents([.year, .month], from: shifted)
        guard let year = result.year, let month = result.month else { return nil }
        return (year, month)
    }

    private func isDay(_ day: DayKey, inYear year: Int, month: Int) -> Bool {
        guard let date = CalendarSupport.date(for: day) else { return false }
        let components = Calendar.autoupdatingCurrent.dateComponents([.year, .month], from: date)
        return components.year == year && components.month == month
    }

    // MARK: - Daily status

    func dailyStatus(for item: DailyItem) -> DailyStatus {
        statusCalculator.dailyStatus(for: item, now: now)
    }

    func dayStatus(for summary: DaySummary) -> DailyStatus? {
        statusCalculator.dayStatus(for: summary, now: now)
    }

    func workStatus(for task: WorkTask) -> WorkStatus {
        statusCalculator.workStatus(for: task, now: now)
    }

    // MARK: - Daily mutations

    @discardableResult
    func quickAddDailyItem(_ content: String) async -> Bool {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        let plannedAt = CalendarSupport.date(on: selectedDay, hour: 18, minute: 0) ?? now

        do {
            _ = try await store.addDailyItem(
                planDate: selectedDay,
                content: text,
                plannedAt: plannedAt,
                now: Date()
            )
            now = Date()
            await reloadDaily()
            await reloadSummaries()
            return true
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    func saveDailyItem(_ item: DailyItem) async -> Bool {
        do {
            let targetDay = item.planDate
            try await store.updateDailyItem(item, now: Date())
            now = Date()

            if targetDay != selectedDay {
                selectedDay = targetDay
                if let date = CalendarSupport.date(for: targetDay) {
                    let components = Calendar.autoupdatingCurrent.dateComponents(
                        [.year, .month],
                        from: date
                    )
                    calendarYear = components.year ?? calendarYear
                    calendarMonth = components.month ?? calendarMonth
                }
            }

            await reloadDaily()
            await reloadSummaries()
            return true
        } catch {
            present(error)
            return false
        }
    }

    func toggleDailyCompletion(_ item: DailyItem) async {
        let actualAt: Date? = item.isCompleted ? nil : Date()

        do {
            try await store.setDailyItemActual(id: item.id, actualAt: actualAt, now: Date())
            now = Date()
            await reloadDaily()
            await reloadSummaries()
        } catch {
            present(error)
        }
    }

    func deleteDailyItem(_ item: DailyItem) async {
        do {
            try await store.deleteDailyItem(id: item.id)
            now = Date()
            await reloadDaily()
            await reloadSummaries()
        } catch {
            present(error)
        }
    }

    // MARK: - Work mutations

    func selectWorkTask(_ id: UUID?) async {
        selectedWorkTaskID = id
        await reloadProgress()
    }

    @discardableResult
    func createWorkTask(
        title: String,
        plannedAt: Date,
        richContent: NSAttributedString
    ) async -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            presentMessage("工作内容不能为空")
            return false
        }

        let taskID = UUID()
        var savedPath: String?

        do {
            let saved = try richTextStore.save(attributedString: richContent, for: taskID)
            savedPath = saved.relativePath

            let task = try await store.addWorkTask(
                id: taskID,
                title: normalizedTitle,
                contentPath: saved.relativePath,
                contentPlain: saved.plainText,
                plannedAt: plannedAt,
                now: Date()
            )
            selectedWorkTaskID = task.id
            now = Date()
            await reloadWork()
            return true
        } catch {
            if let savedPath {
                _ = richTextStore.delete(relativePath: savedPath)
            }
            present(error)
            return false
        }
    }

    @discardableResult
    func updateWorkTask(
        _ task: WorkTask,
        title: String,
        plannedAt: Date,
        richContent: NSAttributedString
    ) async -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            presentMessage("工作内容不能为空")
            return false
        }

        do {
            let saved = try richTextStore.save(attributedString: richContent, for: task.id)
            var updated = workTasks.first { $0.id == task.id } ?? task
            updated.title = normalizedTitle
            updated.plannedAt = plannedAt
            updated.contentPath = saved.relativePath
            updated.contentPlain = saved.plainText

            try await store.updateWorkTask(updated, now: Date())
            now = Date()
            await reloadWork()
            return true
        } catch {
            present(error)
            return false
        }
    }

    func setWorkTaskCompleted(_ task: WorkTask, completed: Bool) async {
        do {
            try await store.setWorkTaskActual(
                id: task.id,
                actualAt: completed ? Date() : nil,
                now: Date()
            )
            now = Date()
            await reloadWork()
        } catch {
            present(error)
        }
    }

    @discardableResult
    func updateWorkActualTime(_ task: WorkTask, actualAt: Date) async -> Bool {
        do {
            try await store.setWorkTaskActual(id: task.id, actualAt: actualAt, now: Date())
            now = Date()
            await reloadWork()
            return true
        } catch {
            present(error)
            return false
        }
    }

    func deleteWorkTask(_ task: WorkTask) async {
        do {
            let paths = try await store.deleteWorkTask(id: task.id)
            for path in paths {
                _ = richTextStore.delete(relativePath: path)
            }
            if selectedWorkTaskID == task.id {
                selectedWorkTaskID = nil
            }
            now = Date()
            await reloadWork()
        } catch {
            present(error)
        }
    }

    func attributedContent(for task: WorkTask) -> NSAttributedString {
        richTextStore.load(
            relativePath: task.contentPath,
            fallbackPlainText: task.contentPlain
        ).attributedString
    }

    func attributedContent(for progress: WorkProgress) -> NSAttributedString {
        richTextStore.load(
            relativePath: progress.contentPath,
            fallbackPlainText: progress.contentPlain
        ).attributedString
    }

    // MARK: - Progress mutations

    @discardableResult
    func addProgress(to task: WorkTask, richContent: NSAttributedString) async -> Bool {
        guard !richTextStore.isBlank(richContent) else {
            presentMessage("进展内容不能为空")
            return false
        }

        let progressID = UUID()
        var savedPath: String?

        do {
            let saved = try richTextStore.save(attributedString: richContent, for: progressID)
            savedPath = saved.relativePath

            _ = try await store.addProgress(
                id: progressID,
                taskID: task.id,
                contentPath: saved.relativePath,
                contentPlain: saved.plainText,
                now: Date()
            )
            await reloadProgress()
            return true
        } catch {
            if let savedPath {
                _ = richTextStore.delete(relativePath: savedPath)
            }
            present(error)
            return false
        }
    }

    @discardableResult
    func updateProgress(_ progress: WorkProgress, richContent: NSAttributedString) async -> Bool {
        guard !richTextStore.isBlank(richContent) else {
            presentMessage("进展内容不能为空")
            return false
        }

        do {
            let saved = try richTextStore.save(attributedString: richContent, for: progress.id)
            var updated = progressEntries.first { $0.id == progress.id } ?? progress
            updated.contentPath = saved.relativePath
            updated.contentPlain = saved.plainText

            try await store.updateProgress(updated, now: Date())
            await reloadProgress()
            return true
        } catch {
            present(error)
            return false
        }
    }

    func deleteProgress(_ progress: WorkProgress) async {
        do {
            if let path = try await store.deleteProgress(id: progress.id) {
                _ = richTextStore.delete(relativePath: path)
            }
            await reloadProgress()
        } catch {
            present(error)
        }
    }

    // MARK: - Maintenance

    @discardableResult
    func createBackupNow() async -> Bool {
        await createBackup(auto: false) != nil
    }

    private func performDailyBackupIfNeeded() async {
        guard !isBackingUp else { return }
        guard backupService.needsBackup(now: now) else {
            lastBackupDate = backupService.lastBackupDate()
            return
        }
        _ = await createBackup(auto: true)
    }

    private func createBackup(auto: Bool) async -> URL? {
        guard !isBackingUp else { return nil }
        isBackingUp = true
        defer {
            isBackingUp = false
            lastBackupDate = backupService.lastBackupDate()
        }

        let staging: BackupStaging
        do {
            staging = try backupService.beginStaging()
        } catch {
            handleBackupFailure(error, auto: auto)
            return nil
        }

        do {
            try await store.snapshotDatabase(to: staging.databaseURL)
            _ = try backupService.copyAttachments(into: staging)
            let backupURL = try backupService.finish(staging: staging, now: Date())
            backupStatusMessage = auto ? "今日自动备份已完成" : "手动备份已完成"
            logger.info("Backup created at \(backupURL.path, privacy: .private)")
            return backupURL
        } catch {
            backupService.cancel(staging: staging)
            handleBackupFailure(error, auto: auto)
            return nil
        }
    }

    private func handleBackupFailure(_ error: Error, auto: Bool) {
        logger.error("Backup failed: \(error.localizedDescription, privacy: .private)")
        let message = "备份失败：\(error.localizedDescription)"
        backupStatusMessage = message
        if !auto {
            presentMessage(message)
        }
    }

    @discardableResult
    func exportData(to parentDirectory: URL) async -> URL? {
        do {
            let export = try backupService.beginExport(in: parentDirectory, now: Date())
            do {
                try await store.snapshotDatabase(to: export.databaseURL)
                _ = try backupService.copyAttachments(into: export)
                try backupService.writeRestoreGuide(into: export.directoryURL)
                backupStatusMessage = "数据已导出到：\(export.directoryURL.lastPathComponent)"
                return export.directoryURL
            } catch {
                try? FileManager.default.removeItem(at: export.directoryURL)
                throw error
            }
        } catch {
            present(error)
            return nil
        }
    }

    private func cleanupOrphanAttachments() async {
        do {
            let referenced = try await store.referencedContentPaths()
            let removed = try richTextStore.sweepOrphans(referencedPaths: referenced)
            if !removed.isEmpty {
                logger.info("Removed \(removed.count) orphan rich text packages")
            }
        } catch {
            logger.error("Orphan cleanup failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func revealDataDirectory() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: paths.rootURL.path)
    }

    func revealBackupsDirectory() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: paths.backupsURL.path)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Errors

    func present(_ error: Error) {
        logger.error("Operation failed: \(error.localizedDescription, privacy: .private)")
        errorMessage = error.localizedDescription
    }

    func presentMessage(_ message: String) {
        errorMessage = message
    }

    func clearError() {
        errorMessage = nil
    }
}
