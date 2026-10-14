import Foundation
import SQLite3

public enum RepositoryError: Error, LocalizedError {
    case database(String)
    public var errorDescription: String? { if case let .database(s) = self { return s }; return nil }
}

/// A single connection, owned by the main thread. Durable edge writes, bounded event retention.
public final class Repository {
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public private(set) var eventRevision: UInt64 = 0
    public let url: URL
    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw RepositoryError.database("无法打开本地数据库：\(url.path)")
        }
        sqlite3_busy_timeout(db, 3000)
        try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON;")
        try execute("""
        CREATE TABLE IF NOT EXISTS sessions(id TEXT PRIMARY KEY, start REAL NOT NULL, payload BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS focus(id TEXT PRIMARY KEY, start REAL NOT NULL, payload BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS hydration(id TEXT PRIMARY KEY, start REAL NOT NULL, payload BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS events(id TEXT PRIMARY KEY, start REAL NOT NULL, payload BLOB NOT NULL);
        CREATE INDEX IF NOT EXISTS events_start ON events(start);
        CREATE TABLE IF NOT EXISTS preferences(id TEXT PRIMARY KEY, start REAL NOT NULL, payload BLOB NOT NULL);
        PRAGMA user_version=1;
        """)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    deinit { sqlite3_close(db) }
    private func execute(_ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { throw error() }
    }
    private func error() -> RepositoryError { .database(String(cString: sqlite3_errmsg(db))) }
    public func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try body(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }
    private func put<T: Encodable>(_ item: T, table: String, id: String, date: Date) throws {
        let data = try encoder.encode(item)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO \(table)(id,start,payload) VALUES(?,?,?)", -1, &statement, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, id, -1, transient)
        sqlite3_bind_double(statement, 2, date.timeIntervalSince1970)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32(data.count), transient) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw error() }
    }
    private func read<T: Decodable>(_ type: T.Type, table: String, suffix: String = "ORDER BY start") throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM \(table) \(suffix)", -1, &statement, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        var result: [T] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw error() }
            result.append(try decoder.decode(type, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))))
        }
        return result
    }
    public func save(_ session: Session) throws { try put(session, table: "sessions", id: session.id.uuidString, date: session.start) }
    public func save(_ session: FocusSession) throws { try put(session, table: "focus", id: session.id.uuidString, date: session.start) }
    public func save(_ event: HydrationEvent) throws { try put(event, table: "hydration", id: event.id.uuidString, date: event.timestamp) }
    public func save(_ event: SystemEvent) throws {
        try put(event, table: "events", id: event.id.uuidString, date: event.timestamp)
        eventRevision &+= 1
    }
    public func saveSettings(_ value: AppSettings) throws { try put(value, table: "preferences", id: "settings", date: Date()) }
    public func saveCheckpoint(_ value: Checkpoint) throws { try put(value, table: "preferences", id: "checkpoint", date: value.timestamp) }
    public func sessions() throws -> [Session] { try read(Session.self, table: "sessions") }
    public func focuses() throws -> [FocusSession] { try read(FocusSession.self, table: "focus") }
    public func hydration() throws -> [HydrationEvent] { try read(HydrationEvent.self, table: "hydration") }
    public func events(limit: Int = 500) throws -> [SystemEvent] { try read(SystemEvent.self, table: "events", suffix: "ORDER BY start DESC LIMIT \(max(1, limit))") }
    public func settings() throws -> AppSettings { try read(AppSettings.self, table: "preferences", suffix: "WHERE id='settings'").first ?? AppSettings() }
    public func checkpoint() throws -> Checkpoint? { try read(Checkpoint.self, table: "preferences", suffix: "WHERE id='checkpoint'").first }
    public func pruneEvents(before: Date) throws {
        try execute("DELETE FROM events WHERE start < \(before.timeIntervalSince1970)")
        if sqlite3_changes(db) > 0 { eventRevision &+= 1 }
    }
    public func backup(to destination: URL) throws {
        var target: OpaquePointer?
        guard sqlite3_open(destination.path, &target) == SQLITE_OK else { throw error() }
        defer { sqlite3_close(target) }
        guard let backup = sqlite3_backup_init(target, "main", db, "main") else { throw error() }
        let status = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
        guard status == SQLITE_DONE else { throw error() }
    }
}
