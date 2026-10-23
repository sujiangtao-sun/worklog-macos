import Foundation

enum Migrations {
    static let currentVersion: Int64 = 1

    static func migrate(_ database: SQLiteConnection) throws {
        let version = try database.scalarInt64("PRAGMA user_version;") ?? 0

        guard version <= currentVersion else {
            throw WorkLogDatabaseError.unsupportedSchema(version)
        }
        guard version < currentVersion else { return }

        try database.transaction {
            if version < 1 {
                try database.execute(
                    """
                    CREATE TABLE IF NOT EXISTS daily_items (
                        id TEXT PRIMARY KEY NOT NULL,
                        plan_date TEXT NOT NULL,
                        sort_index INTEGER NOT NULL,
                        content TEXT NOT NULL,
                        planned_at INTEGER NOT NULL,
                        actual_at INTEGER,
                        difficulty TEXT NOT NULL DEFAULT '',
                        feedback TEXT NOT NULL DEFAULT '',
                        created_at INTEGER NOT NULL,
                        updated_at INTEGER NOT NULL
                    );

                    CREATE INDEX IF NOT EXISTS idx_daily_items_day
                        ON daily_items(plan_date, sort_index, created_at);

                    CREATE TABLE IF NOT EXISTS work_tasks (
                        id TEXT PRIMARY KEY NOT NULL,
                        title TEXT NOT NULL,
                        content_path TEXT,
                        content_plain TEXT NOT NULL DEFAULT '',
                        planned_at INTEGER NOT NULL,
                        actual_at INTEGER,
                        created_at INTEGER NOT NULL,
                        updated_at INTEGER NOT NULL
                    );

                    CREATE INDEX IF NOT EXISTS idx_work_tasks_planned
                        ON work_tasks(planned_at);
                    CREATE INDEX IF NOT EXISTS idx_work_tasks_actual
                        ON work_tasks(actual_at);

                    CREATE TABLE IF NOT EXISTS work_progress (
                        id TEXT PRIMARY KEY NOT NULL,
                        task_id TEXT NOT NULL REFERENCES work_tasks(id) ON DELETE CASCADE,
                        content_path TEXT,
                        content_plain TEXT NOT NULL DEFAULT '',
                        created_at INTEGER NOT NULL,
                        updated_at INTEGER NOT NULL
                    );

                    CREATE INDEX IF NOT EXISTS idx_work_progress_task
                        ON work_progress(task_id, created_at);
                    """
                )
            }

            try database.execute("PRAGMA user_version = \(currentVersion);")
        }
    }
}
