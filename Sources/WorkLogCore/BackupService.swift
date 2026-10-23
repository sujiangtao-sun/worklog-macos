import Foundation

public enum BackupServiceError: Error, LocalizedError, Sendable {
    case directoryCreationFailed(String)
    case backupMoveFailed(String)
}

public struct BackupStaging: Sendable {
    public let directoryURL: URL

    public var databaseURL: URL {
        directoryURL.appendingPathComponent("worklog.sqlite", isDirectory: false)
    }

    public var attachmentsURL: URL {
        directoryURL.appendingPathComponent("attachments", isDirectory: true)
    }
}

public struct BackupService: Sendable {
    public let paths: DataPaths

    public init(paths: DataPaths) {
        self.paths = paths
    }

    public static func backupIsDue(
        lastBackupDate: Date?,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard let lastBackupDate else { return true }
        return !calendar.isDate(lastBackupDate, inSameDayAs: now)
    }

    public func lastBackupDate() -> Date? {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: paths.backupsURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let dates = entries.compactMap { entry -> Date? in
            guard entry.lastPathComponent.hasPrefix("backup-") else { return nil }
            let values = try? entry.resourceValues(
                forKeys: [.creationDateKey, .contentModificationDateKey, .isDirectoryKey]
            )
            guard values?.isDirectory == true else { return nil }
            return values?.creationDate ?? values?.contentModificationDate
        }
        return dates.max()
    }

    public func needsBackup(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Bool {
        Self.backupIsDue(lastBackupDate: lastBackupDate(), now: now, calendar: calendar)
    }

    public func beginStaging() throws -> BackupStaging {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: paths.backupsURL, withIntermediateDirectories: true)

        let staging = paths.backupsURL.appendingPathComponent(
            ".staging-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(
                at: staging.appendingPathComponent("attachments", isDirectory: true),
                withIntermediateDirectories: true
            )
        } catch {
            throw BackupServiceError.directoryCreationFailed(error.localizedDescription)
        }
        return BackupStaging(directoryURL: staging)
    }

    @discardableResult
    public func copyAttachments(into staging: BackupStaging) throws -> Int {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: paths.attachmentsURL.path) else { return 0 }

        let entries = try fileManager.contentsOfDirectory(
            at: paths.attachmentsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        try fileManager.createDirectory(
            at: staging.attachmentsURL,
            withIntermediateDirectories: true
        )

        var copied = 0
        for entry in entries {
            let target = staging.attachmentsURL.appendingPathComponent(entry.lastPathComponent)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: entry, to: target)
            copied += 1
        }
        return copied
    }

    public func finish(staging: BackupStaging, now: Date = Date()) throws -> URL {
        let fileManager = FileManager.default
        let baseName = "backup-\(timestamp(now))"
        var finalURL = paths.backupsURL.appendingPathComponent(baseName, isDirectory: true)

        if fileManager.fileExists(atPath: finalURL.path) {
            let suffix = UUID().uuidString.prefix(6)
            finalURL = paths.backupsURL.appendingPathComponent(
                "\(baseName)-\(suffix)",
                isDirectory: true
            )
        }

        do {
            try fileManager.moveItem(at: staging.directoryURL, to: finalURL)
        } catch {
            throw BackupServiceError.backupMoveFailed(error.localizedDescription)
        }

        try prune()
        return finalURL
    }

    public func cancel(staging: BackupStaging) {
        try? FileManager.default.removeItem(at: staging.directoryURL)
    }

    @discardableResult
    public func prune(keep: Int = 7) throws -> Int {
        let fileManager = FileManager.default
        let retained = max(keep, 1)

        let entries = try fileManager.contentsOfDirectory(
            at: paths.backupsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let backups = entries
            .filter { $0.lastPathComponent.hasPrefix("backup-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        var removed = 0
        for entry in backups.dropFirst(retained) {
            try fileManager.removeItem(at: entry)
            removed += 1
        }
        return removed
    }

    public func beginExport(in parentDirectory: URL, now: Date = Date()) throws -> BackupStaging {
        let fileManager = FileManager.default
        let baseName = "WorkLog-Export-\(timestamp(now))"
        var directory = parentDirectory.appendingPathComponent(baseName, isDirectory: true)

        if fileManager.fileExists(atPath: directory.path) {
            directory = parentDirectory.appendingPathComponent(
                "\(baseName)-\(UUID().uuidString.prefix(6))",
                isDirectory: true
            )
        }

        do {
            try fileManager.createDirectory(
                at: directory.appendingPathComponent("attachments", isDirectory: true),
                withIntermediateDirectories: true
            )
        } catch {
            throw BackupServiceError.directoryCreationFailed(error.localizedDescription)
        }
        return BackupStaging(directoryURL: directory)
    }

    public func writeRestoreGuide(into directory: URL) throws {
        let guide = """
        恢复方法
        ========
        1. 退出“待办进展”。
        2. 将本目录中的 worklog.sqlite 和 attachments 文件夹复制到：
           ~/Library/Application Support/WorkLog/
        3. 覆盖同名文件前，建议先备份现有数据目录。
        4. 重新打开应用。

        说明：worklog.sqlite 是数据库，attachments 保存富文本中的图片等附件。
        """
        let url = directory.appendingPathComponent("恢复说明.txt", isDirectory: false)
        try guide.write(to: url, atomically: true, encoding: .utf8)
    }

    private func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: date)
    }
}
