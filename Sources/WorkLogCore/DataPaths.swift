import Foundation

public enum DataPathsError: Error, LocalizedError, Sendable {
    case invalidRelativePath(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRelativePath(let path):
            "无效的附件路径：\(path)"
        }
    }
}

public struct DataPaths: Sendable {
    public let rootURL: URL
    public let backupsURL: URL

    public var databaseURL: URL {
        rootURL.appendingPathComponent("worklog.sqlite", isDirectory: false)
    }

    public var attachmentsURL: URL {
        rootURL.appendingPathComponent("attachments", isDirectory: true)
    }

    public init(
        rootURL: URL? = nil,
        backupsURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        let resolvedRoot: URL
        if let rootURL {
            resolvedRoot = rootURL.standardizedFileURL
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            resolvedRoot = appSupport.appendingPathComponent("WorkLog", isDirectory: true)
        }

        let resolvedBackups: URL
        if let backupsURL {
            resolvedBackups = backupsURL.standardizedFileURL
        } else {
            resolvedBackups = resolvedRoot
                .deletingLastPathComponent()
                .appendingPathComponent("WorkLogBackups", isDirectory: true)
        }

        self.rootURL = resolvedRoot
        self.backupsURL = resolvedBackups

        try fileManager.createDirectory(
            at: resolvedRoot.appendingPathComponent("attachments", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: resolvedBackups,
            withIntermediateDirectories: true
        )
    }

    public static func attachmentRelativePath(for id: UUID) -> String {
        "attachments/\(id.uuidString).rtfd"
    }

    public func fileURL(forAttachmentRelativePath relativePath: String) throws -> URL {
        guard relativePath.hasPrefix("attachments/"),
              !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..") else {
            throw DataPathsError.invalidRelativePath(relativePath)
        }

        let candidate = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        let base = attachmentsURL.standardizedFileURL.path
        guard candidate.path.hasPrefix(base + "/") else {
            throw DataPathsError.invalidRelativePath(relativePath)
        }
        return candidate
    }
}
