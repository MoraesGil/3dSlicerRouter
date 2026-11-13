import Foundation
import SQLite3

/// Memória do router. O xattr no arquivo basta; o SQLite é índice/histórico e pode faltar.
final class Store {
    static let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("3dSlicerRouter", isDirectory: true)

    private var db: OpaquePointer?
    private let coder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL = Store.supportDir) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("router.sqlite").path
        if sqlite3_open(path, &db) != SQLITE_OK { db = nil; return }
        sqlite3_busy_timeout(db, 1000)
        exec("""
        CREATE TABLE IF NOT EXISTS files(uuid TEXT PRIMARY KEY, path TEXT, record TEXT, updated_at REAL);
        CREATE INDEX IF NOT EXISTS files_path ON files(path);
        CREATE TABLE IF NOT EXISTS printers(model TEXT PRIMARY KEY, app TEXT);
        CREATE TABLE IF NOT EXISTS events(ts REAL, uuid TEXT, path TEXT, printer_model TEXT, app TEXT, reason TEXT);
        CREATE TABLE IF NOT EXISTS catalog(path TEXT PRIMARY KEY, kind TEXT, size INTEGER, mtime REAL, printer TEXT,
          plates INTEGER, embedded INTEGER, preview TEXT, error TEXT, indexed_at REAL);
        """)
    }

    deinit { sqlite3_close(db) }

    // MARK: arquivo

    func record(for url: URL) -> FileRecord? {
        let portable = FileRecord.read(from: url)
        // Sem xattr (cópia por zip/upload, por exemplo): tenta o índice pelo caminho.
        let local = query("SELECT record FROM files WHERE path = ? OR (uuid = ? AND uuid <> '') ORDER BY (uuid = ? AND uuid <> '') DESC, updated_at DESC LIMIT 1", [url.path, portable?.uuid ?? "", portable?.uuid ?? ""])
            .first.flatMap { try? decoder.decode(FileRecord.self, from: Data($0.utf8)) }
        return RoutingPreferences.trustedRecord(portable: portable, local: local)
    }

    func save(_ record: FileRecord, for url: URL, reason: String) {
        // Serialize identity assignment with other Router processes using the same database.
        guard let db, sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { return }
        var saved = record
        if let previousPath = query("SELECT path FROM files WHERE uuid = ?", [record.uuid]).first,
           previousPath != url.path {
            // The old path may be offline, so never reuse its identity at a different path.
            saved.uuid = UUID().uuidString
        }
        guard let data = try? coder.encode(saved) else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return
        }
        let json = String(decoding: data, as: UTF8.self)
        // A new identity for an existing path must not leave a stale competing row.
        guard run("DELETE FROM files WHERE path = ? AND uuid <> ?", [url.path, saved.uuid]),
              run("INSERT OR REPLACE INTO files(uuid, path, record, updated_at) VALUES(?, ?, ?, ?)",
                  [saved.uuid, url.path, json, Date().timeIntervalSince1970]),
              run("INSERT INTO events VALUES(?, ?, ?, ?, ?, ?)",
                  [Date().timeIntervalSince1970, saved.uuid, url.path, saved.printerModel ?? "", saved.app.bundleID, reason]),
              sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return
        }
        saved.write(to: url)
        RouterFileIcon.apply(to: url, app: saved.app)
    }

    func forget(_ url: URL) {
        FileRecord.remove(from: url)
        RouterFileIcon.remove(from: url)
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

    // MARK: catálogo (indexador)

    func isCatalogued(_ path: String, size: Int, modified: Date) -> Bool {
        guard let preview = query("SELECT CASE WHEN kind = 'gcode' AND embedded = 1 THEN 'embedded-gcode' ELSE preview END FROM catalog WHERE path = ? AND size = ? AND mtime = ? AND error = ''",
                                  [path, Double(size), modified.timeIntervalSince1970]).first else { return false }
        if preview == "embedded-gcode" { return true }
        if size > Indexer.maxRenderBytes { return true }
        return !preview.isEmpty && URL(fileURLWithPath: preview).lastPathComponent == PreviewCache.name(for: URL(fileURLWithPath: path))
            && FileManager.default.fileExists(atPath: preview)
    }

    func upsertCatalog(_ e: Indexer.Entry) {
        run("INSERT OR REPLACE INTO catalog VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [e.path, e.kind, Double(e.size), e.modified.timeIntervalSince1970, e.printer ?? "",
             Double(e.plates), Double(e.embedded ? 1 : 0), e.preview ?? "", e.error ?? "", Date().timeIntervalSince1970])
    }

    func pruneCatalog(keeping paths: Set<String>) {
        for path in query("SELECT path FROM catalog", []) where !paths.contains(path)
            && !FileManager.default.fileExists(atPath: path) {
            run("DELETE FROM catalog WHERE path = ?", [path])
        }
    }

    /// Linhas "tipo\timpressora\tpreview\tcaminho", filtradas por trecho do caminho ou da impressora.
    func catalog(matching filter: String?) -> [String] {
        let like = "%\(filter ?? "")%"
        return query("""
            SELECT kind || char(9) || printer || char(9) ||
              CASE WHEN error <> '' THEN 'erro' WHEN embedded = 1 THEN 'embutido' WHEN preview <> '' THEN 'render' ELSE '-' END
              || char(9) || path FROM catalog WHERE path LIKE ? OR printer LIKE ? ORDER BY mtime DESC
            """, [like, like])
    }

    func catalogStats() -> String {
        query("""
            SELECT count(*) || ' arquivos: ' || sum(kind = '3mf') || ' .3mf, ' || sum(kind = 'gcode') || ' .gcode; ' ||
              sum(embedded = 1) || ' com thumbnail embutida, ' || sum(preview <> '') || ' renderizados, ' ||
              sum(error <> '') || ' com erro' FROM catalog
            """, []).first ?? "catálogo vazio"
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

    @discardableResult
    private func run(_ sql: String, _ args: [Any]) -> Bool {
        guard let stmt = prepare(sql, args) else { return false }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_DONE
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
