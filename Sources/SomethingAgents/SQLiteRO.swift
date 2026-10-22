// SQLiteRO: a harness's SQLite database, opened read-only. Codex and OpenCode keep their sessions in
// SQLite files that their programs write while something reads, so the file is opened with `mode=ro` and never
// `immutable`, which would ignore what a live writer left in its write-ahead log. Each database comes with a whitelist
// of the tables and columns its reader may use: the schema guard checks they are all there, and a query that would
// return any other column as it is stored (a message's whole `data`, a secret) is refused.
import Foundation
import SQLite3

package final class SQLiteRO {
    package struct Failure: Error, Equatable { package let message: String }

    /// The tables and columns a reader may use, by table name.
    let whitelist: [String: Set<String>]
    private var db: OpaquePointer?

    /// Opens `path` read-only. Throws Failure when the file is missing or SQLite cannot open it (a database in WAL
    /// mode whose `-shm` file is gone cannot be opened read-only): the reader then says it cannot read.
    package init(_ path: String, whitelist: [String: Set<String>]) throws {
        self.whitelist = whitelist
        guard FileManager.default.fileExists(atPath: path) else { throw Failure(message: "no file") }
        // The URI form takes mode=ro; the path is percent-encoded by URL, so a "?" or "#" in a folder name stays a name.
        let uri = URL(fileURLWithPath: path).absoluteString + "?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            sqlite3_close(db)
            db = nil
            throw Failure(message: message)
        }
        // A writer holds its lock for milliseconds; a tick may wait that long, never longer.
        sqlite3_busy_timeout(db, 200)
        // SQLite opens lazily: the first read says whether the file can be read at all.
        _ = try run("SELECT count(*) FROM sqlite_master", [], checked: false)
    }

    deinit { sqlite3_close(db) }

    /// The columns of each table of the database, read from its schema only.
    package func tables() throws -> [String: Set<String>] {
        var tables: [String: Set<String>] = [:]
        for row in try run("SELECT name FROM sqlite_master WHERE type = 'table'", [], checked: false) {
            guard let name = row["name"] as? String else { continue }
            let columns = try run("SELECT name FROM pragma_table_info(?)", [name], checked: false).compactMap { $0["name"] as? String }
            tables[name] = Set(columns)
        }
        return tables
    }

    /// Whether every table and column of `whitelist` (all of it when nil) is in the database. Throws Failure when its
    /// schema cannot be read.
    package func guarded(_ needs: [String: Set<String>]? = nil) throws -> Bool {
        let tables = try tables()
        return (needs ?? whitelist).allSatisfy { table, columns in tables[table].map(columns.isSubset) ?? false }
    }

    /// The rows of `sql` with `values` bound to its `?` in order, as dictionaries by result column name; a NULL is
    /// left out of its row. Throws Failure when SQLite refuses the query, or when a result column is a stored column
    /// outside the whitelist (an expression over one, such as `json_extract(data, '$.text')`, is the reader's choice).
    package func rows(_ sql: String, _ values: [Any] = []) throws -> [[String: Any]] { try run(sql, values, checked: true) }

    private func run(_ sql: String, _ values: [Any], checked: Bool) throws -> [[String: Any]] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
        let count = sqlite3_column_count(statement)
        if checked {
            for column in 0..<count {
                guard let origin = sqlite3_column_origin_name(statement, column), let table = sqlite3_column_table_name(statement, column) else { continue }
                let (name, owner) = (String(cString: origin), String(cString: table))
                guard whitelist[owner]?.contains(name) == true else { throw Failure(message: "\(owner).\(name) is not on the whitelist") }
            }
        }
        // SQLite copies a text it is given with this destructor, so the Swift string may go once bound.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case let text as String: sqlite3_bind_text(statement, position, text, -1, transient)
            case let number as Int64: sqlite3_bind_int64(statement, position, number)
            case let number as Int: sqlite3_bind_int64(statement, position, Int64(number))
            case let number as Double: sqlite3_bind_double(statement, position, number)
            default: sqlite3_bind_null(statement, position)
            }
        }
        var rows: [[String: Any]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return rows }
            guard step == SQLITE_ROW else { throw failure() }
            var row: [String: Any] = [:]
            for column in 0..<count {
                let name = String(cString: sqlite3_column_name(statement, column))
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: row[name] = sqlite3_column_int64(statement, column)
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(statement, column)
                case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(statement, column))
                default: break
                }
            }
            rows.append(row)
        }
    }

    private func failure() -> Failure { Failure(message: String(cString: sqlite3_errmsg(db))) }

    /// A number SQLite gave, as an integer or a real (JSON numbers come back as either), or nil.
    package static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as Int64: return Double(number)
        case let number as Double: return number
        default: return nil
        }
    }
}
