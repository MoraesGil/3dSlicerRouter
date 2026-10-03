import Foundation
import SQLite3

/// Memória do router. O xattr no arquivo basta; o SQLite é índice/histórico e pode faltar.
final class Store {
    static let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("3dSlicerRouter", isDirectory: true)

    private var db: OpaquePointer?
    private let coder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        try? FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        let path = Self.supportDir.appendingPathComponent("router.sqlite").path
        if sqlite3_open(path, &db) != SQLITE_OK { db = nil; return }
        exec("""
        CREATE TABLE IF NOT EXISTS files(uuid TEXT PRIMARY KEY, path TEXT, record TEXT, updated_at REAL);
        CREATE INDEX IF NOT EXISTS files_path ON files(path);
        CREATE TABLE IF NOT EXISTS printers(model TEXT PRIMARY KEY, app TEXT);
        CREATE TABLE IF NOT EXISTS events(ts REAL, uuid TEXT, path TEXT, printer_model TEXT, app TEXT, reason TEXT);
        """)
    }

    deinit { sqlite3_close(db) }

    // MARK: arquivo

    func record(for url: URL) -> FileRecord? {
        if let r = FileRecord.read(from: url) { return r }
        // Sem xattr (cópia por zip/upload, por exemplo): tenta o índice pelo caminho.
        return query("SELECT record FROM files WHERE path = ? ORDER BY updated_at DESC LIMIT 1", [url.path])
            .first.flatMap { try? decoder.decode(FileRecord.self, from: Data($0.utf8)) }
    }

    func save(_ record: FileRecord, for url: URL, reason: String) {
        guard let data = try? coder.encode(record) else { return }
        record.write(to: url)
        let json = String(decoding: data, as: UTF8.self)
        run("INSERT OR REPLACE INTO files(uuid, path, record, updated_at) VALUES(?, ?, ?, ?)",
            [record.uuid, url.path, json, Date().timeIntervalSince1970])
        run("INSERT INTO events VALUES(?, ?, ?, ?, ?, ?)",
            [Date().timeIntervalSince1970, record.uuid, url.path, record.printerModel ?? "", record.app.bundleID, reason])
    }

    func forget(_ url: URL) {
        FileRecord.remove(from: url)
        run("DELETE FROM files WHERE path = ?", [url.path])
    }

    // MARK: impressoras

    func mappings() -> Mappings {
        var m = Mappings()
        for row in query("SELECT model || char(9) || app FROM printers", []) {
            let parts = row.split(separator: "\t", maxSplits: 1).map(String.init)
            if parts.count == 2, let app = try? decoder.decode(SlicerApp.self, from: Data(parts[1].utf8)) {
                m.byModel[parts[0]] = app
            }
        }
        return m
    }

    func remember(printer model: String, app: SlicerApp) {
        guard let data = try? coder.encode(app) else { return }
        run("INSERT OR REPLACE INTO printers(model, app) VALUES(?, ?)", [model, String(decoding: data, as: UTF8.self)])
    }

    // MARK: SQLite

    private func exec(_ sql: String) { sqlite3_exec(db, sql, nil, nil, nil) }

    private func prepare(_ sql: String, _ args: [Any]) -> OpaquePointer? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, arg) in args.enumerated() {
            switch arg {
            case let d as Double: sqlite3_bind_double(stmt, Int32(i + 1), d)
            default: sqlite3_bind_text(stmt, Int32(i + 1), "\(arg)", -1, transient)
            }
        }
        return stmt
    }

    private func run(_ sql: String, _ args: [Any]) {
        guard let stmt = prepare(sql, args) else { return }
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    private func query(_ sql: String, _ args: [Any]) -> [String] {
        guard let stmt = prepare(sql, args) else { return [] }
        defer { sqlite3_finalize(stmt) }
        var rows: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) { rows.append(String(cString: c)) }
        }
        return rows
    }
}
