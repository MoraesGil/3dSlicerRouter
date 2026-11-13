import Foundation
import SQLite3

/// Read-only snapshot for Quick Look. Do not create a database from an extension.
public struct RoutingPreferences {
    public var record: FileRecord?
    public var mappings = Mappings()

    public static let directory = PreviewCache.directory.deletingLastPathComponent()

    /// A document may carry a portable hint, but cannot authorize an arbitrary local app.
    public static func trustedRecord(portable: FileRecord?, local: FileRecord?) -> FileRecord? {
        // The portable UUID helps find our own confirmed choice after a local copy.
        // A foreign file's application path is never authority to launch an app.
        local
    }

    public static func read(for url: URL, directory: URL = directory) -> RoutingPreferences {
        let portable = FileRecord.read(from: url)
        var result = RoutingPreferences(record: trustedRecord(portable: portable, local: nil))
        var db: OpaquePointer?
        let database = directory.appendingPathComponent("router.sqlite").path
        guard FileManager.default.fileExists(atPath: database),
              sqlite3_open_v2(database, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(db); return result
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)
        let decoder = JSONDecoder()
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT record FROM files WHERE path = ? OR (uuid = ? AND uuid <> '') ORDER BY (uuid = ? AND uuid <> '') DESC, updated_at DESC LIMIT 1", -1, &statement, nil) == SQLITE_OK {
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, url.path, -1, transient)
            sqlite3_bind_text(statement, 2, portable?.uuid ?? "", -1, transient)
            sqlite3_bind_text(statement, 3, portable?.uuid ?? "", -1, transient)
            if sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_text(statement, 0) {
                let local = try? decoder.decode(FileRecord.self, from: Data(String(cString: bytes).utf8))
                result.record = trustedRecord(portable: portable, local: local)
            }
        }
        sqlite3_finalize(statement); statement = nil
        if sqlite3_prepare_v2(db, "SELECT model, app FROM printers", -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let model = sqlite3_column_text(statement, 0), let json = sqlite3_column_text(statement, 1),
                      let app = try? decoder.decode(SlicerApp.self, from: Data(String(cString: json).utf8)) else { continue }
                result.mappings.byModel[String(cString: model)] = app
            }
        }
        sqlite3_finalize(statement)
        return result
    }
}
