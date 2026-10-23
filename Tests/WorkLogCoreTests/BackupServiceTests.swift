import Foundation
import Testing
@testable import WorkLogCore

@Suite("Backups")
struct BackupServiceTests {
    @Test("Backup due logic respects local calendar days")
    func dueLogic() {
        let calendar = TestDates.defaultCalendar
        let now = TestDates.date(2026, 10, 23, hour: 8, calendar: calendar)
        let yesterdayLate = TestDates.date(2026, 10, 22, hour: 23, calendar: calendar)
        let todayEarly = TestDates.date(2026, 10, 23, hour: 1, calendar: calendar)

        #expect(BackupService.backupIsDue(lastBackupDate: nil, now: now, calendar: calendar))
        #expect(BackupService.backupIsDue(lastBackupDate: yesterdayLate, now: now, calendar: calendar))
        #expect(!BackupService.backupIsDue(lastBackupDate: todayEarly, now: now, calendar: calendar))
    }

    @Test("Backup snapshot includes database and attachments")
    func backupSnapshot() async throws {
        let env = try TestEnvironment.make()
        defer { env.cleanup() }

        let calendar = TestDates.defaultCalendar
        let day = TestDates.dayKey(
            for: TestDates.date(2026, 10, 23, hour: 12, calendar: calendar),
            calendar: calendar
        )
        _ = try await env.store.addDailyItem(
            planDate: day,
            content: "备份测试",
            plannedAt: TestDates.date(2026, 10, 23, hour: 18, calendar: calendar)
        )

        let attachmentDirectory = env.paths.attachmentsURL
            .appendingPathComponent("sample.rtfd", isDirectory: true)
        try FileManager.default.createDirectory(
            at: attachmentDirectory,
            withIntermediateDirectories: true
        )
        try Data("attachment".utf8).write(
            to: attachmentDirectory.appendingPathComponent("TXT.rtf")
        )

        let service = BackupService(paths: env.paths)
        let staging = try service.beginStaging()
        try await env.store.snapshotDatabase(to: staging.databaseURL)
        let copied = try service.copyAttachments(into: staging)
        #expect(copied == 1)

        let finalURL = try service.finish(
            staging: staging,
            now: TestDates.date(2026, 10, 23, hour: 20, calendar: calendar)
        )

        #expect(
            FileManager.default.fileExists(
                atPath: finalURL.appendingPathComponent("worklog.sqlite").path
            )
        )
        #expect(
            FileManager.default.fileExists(
                atPath: finalURL.appendingPathComponent("attachments/sample.rtfd/TXT.rtf").path
            )
        )

        let backupPaths = try DataPaths(
            rootURL: finalURL,
            backupsURL: env.paths.backupsURL
        )
        let backupStore = try WorkLogStore(paths: backupPaths, calendar: calendar)
        let items = try await backupStore.dailyItems(on: day)
        #expect(items.count == 1)
        #expect(items.first?.content == "备份测试")
    }

    @Test("Retention keeps newest backups")
    func retention() throws {
        let env = try TestEnvironment.make()
        defer { env.cleanup() }

        for index in 1...9 {
            let name = String(format: "backup-2026-01-%02d_000000", index)
            try FileManager.default.createDirectory(
                at: env.paths.backupsURL.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let service = BackupService(paths: env.paths)
        let removed = try service.prune(keep: 7)

        #expect(removed == 2)
        let remaining = try FileManager.default
            .contentsOfDirectory(atPath: env.paths.backupsURL.path)
            .filter { $0.hasPrefix("backup-") }
        #expect(remaining.count == 7)
        #expect(remaining.contains("backup-2026-01-09_000000"))
        #expect(!remaining.contains("backup-2026-01-01_000000"))
    }

    @Test("Export copies a readable dataset and restore guide")
    func export() async throws {
        let env = try TestEnvironment.make()
        defer { env.cleanup() }

        let calendar = TestDates.defaultCalendar
        let day = TestDates.dayKey(
            for: TestDates.date(2026, 10, 23, hour: 12, calendar: calendar),
            calendar: calendar
        )
        _ = try await env.store.addDailyItem(
            planDate: day,
            content: "导出测试",
            plannedAt: TestDates.date(2026, 10, 23, hour: 18, calendar: calendar)
        )

        let parent = env.baseURL.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let service = BackupService(paths: env.paths)
        let export = try service.beginExport(
            in: parent,
            now: TestDates.date(2026, 10, 23, hour: 21, calendar: calendar)
        )
        try await env.store.snapshotDatabase(to: export.databaseURL)
        _ = try service.copyAttachments(into: export)
        try service.writeRestoreGuide(into: export.directoryURL)

        #expect(FileManager.default.fileExists(atPath: export.databaseURL.path))
        #expect(FileManager.default.fileExists(atPath: export.attachmentsURL.path))
        #expect(
            FileManager.default.fileExists(
                atPath: export.directoryURL.appendingPathComponent("恢复说明.txt").path
            )
        )
    }
}
