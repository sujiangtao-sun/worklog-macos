import Foundation
import SQLite3

public enum WorkLogDatabaseError: Error, LocalizedError, Sendable {
    case openFailed(String)
    case statementFailed(sql: String, message: String)
    case bindingFailed(sql: String, message: String)
    case corruptedRow(String)
    case notFound(String)
    case validation(String)
    case backupFailed(String)
    case unsupportedSchema(Int64)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            "无法打开本地数据库：\(message)"
        case .statementFailed(_, let message):
            "数据库操作失败：\(message)"
        case .bindingFailed(_, let message):
            "数据库参数绑定失败：\(message)"
        case .corruptedRow(let message):
            "本地数据记录异常：\(message)"
        case .notFound(let entity):
            "未找到\(entity)，可能已被删除"
        case .validation(let message):
            message
        case .backupFailed(let message):
            "数据备份失败：\(message)"
        case .unsupportedSchema(let version):
            "数据版本 \(version) 高于当前应用支持的版本，请升级应用"
        }
    }
}

final class SQLiteConnection {
    let handle: OpaquePointer

    init(path: String) throws {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &database, flags, nil)

        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "无法打开数据库（错误码 \(result)）"
            if let database {
                sqlite3_close_v2(database)
            }
            throw WorkLogDatabaseError.openFailed(message)
        }

        self.handle = database
        sqlite3_busy_timeout(database, 5_000)
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA synchronous = NORMAL;")
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    var changes: Int {
        Int(sqlite3_changes(handle))
    }

    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)

        guard result == SQLITE_OK else {
            if let errorMessage {
                let message = String(cString: errorMessage)
                sqlite3_free(UnsafeMutableRawPointer(errorMessage))
                throw WorkLogDatabaseError.statementFailed(sql: sql, message: message)
            }
            throw WorkLogDatabaseError.statementFailed(sql: sql, message: lastErrorMessage)
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)

        guard result == SQLITE_OK, let statement else {
            throw WorkLogDatabaseError.statementFailed(sql: sql, message: lastErrorMessage)
        }
        return SQLiteStatement(connection: handle, handle: statement, sql: sql)
    }

    func scalarInt64(_ sql: String) throws -> Int64? {
        let statement = try prepare(sql)
        guard try statement.step() else { return nil }
        return statement.int64(at: 0)
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE;")
        do {
            let value = try body()
            try execute("COMMIT;")
            return value
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func backup(to destinationURL: URL) throws {
        var destination: OpaquePointer?
        let openResult = sqlite3_open_v2(
            destinationURL.path,
            &destination,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard openResult == SQLITE_OK, let destination else {
            let message = destination.map { String(cString: sqlite3_errmsg($0)) }
                ?? "无法创建备份数据库（错误码 \(openResult)）"
            if let destination {
                sqlite3_close_v2(destination)
            }
            throw WorkLogDatabaseError.backupFailed(message)
        }
        defer { sqlite3_close_v2(destination) }

        guard let backupHandle = sqlite3_backup_init(destination, "main", handle, "main") else {
            throw WorkLogDatabaseError.backupFailed(String(cString: sqlite3_errmsg(destination)))
        }

        let stepResult = sqlite3_backup_step(backupHandle, -1)
        let finishResult = sqlite3_backup_finish(backupHandle)

        guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
            let code = stepResult == SQLITE_DONE ? finishResult : stepResult
            throw WorkLogDatabaseError.backupFailed("SQLite 备份错误码 \(code)")
        }
    }

    private var lastErrorMessage: String {
        String(cString: sqlite3_errmsg(handle))
    }
}

final class SQLiteStatement {
    private let connection: OpaquePointer
    private let handle: OpaquePointer
    private let sql: String

    init(connection: OpaquePointer, handle: OpaquePointer, sql: String) {
        self.connection = connection
        self.handle = handle
        self.sql = sql
    }

    deinit {
        sqlite3_finalize(handle)
    }

    func bind(_ value: String?, at index: Int32) throws {
        let result: Int32
        if let value {
            result = value.withCString { pointer in
                sqlite3_bind_text(
                    handle,
                    index,
                    pointer,
                    -1,
                    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                )
            }
        } else {
            result = sqlite3_bind_null(handle, index)
        }
        guard result == SQLITE_OK else {
            throw WorkLogDatabaseError.bindingFailed(sql: sql, message: lastErrorMessage)
        }
    }

    func bind(_ value: Int64, at index: Int32) throws {
        guard sqlite3_bind_int64(handle, index, value) == SQLITE_OK else {
            throw WorkLogDatabaseError.bindingFailed(sql: sql, message: lastErrorMessage)
        }
    }

    func bind(_ value: Int, at index: Int32) throws {
        try bind(Int64(value), at: index)
    }

    func bindNull(at index: Int32) throws {
        guard sqlite3_bind_null(handle, index) == SQLITE_OK else {
            throw WorkLogDatabaseError.bindingFailed(sql: sql, message: lastErrorMessage)
        }
    }

    func step() throws -> Bool {
        let result = sqlite3_step(handle)
        switch result {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw WorkLogDatabaseError.statementFailed(sql: sql, message: lastErrorMessage)
        }
    }

    func isNull(at index: Int32) -> Bool {
        sqlite3_column_type(handle, index) == SQLITE_NULL
    }

    func string(at index: Int32) -> String? {
        guard !isNull(at: index), let pointer = sqlite3_column_text(handle, index) else {
            return nil
        }
        return String(cString: pointer)
    }

    func int64(at index: Int32) -> Int64 {
        sqlite3_column_int64(handle, index)
    }

    func int(at index: Int32) -> Int {
        Int(sqlite3_column_int64(handle, index))
    }

    private var lastErrorMessage: String {
        String(cString: sqlite3_errmsg(connection))
    }
}
