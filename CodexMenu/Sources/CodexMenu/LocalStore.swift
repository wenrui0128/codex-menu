import Foundation
import SQLite3

struct StoreFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class ReadOnlyDatabase {
    private var db: OpaquePointer?

    init(url: URL) throws {
        // SQLITE_OPEN_READONLY is deliberate. No migration or write is ever made.
        let result = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else {
            let detail = db.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            if db != nil { sqlite3_close(db); db = nil }
            throw StoreFailure(message: "无法读取 \(url.lastPathComponent)：\(detail)")
        }
        sqlite3_busy_timeout(db, 250)
    }

    deinit { sqlite3_close(db) }

    func rows(_ sql: String, bindings: [String] = []) throws -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreFailure(message: "会话数据库格式不兼容：\(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in bindings.enumerated() {
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient)
        }
        var result: [[String: String]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW else {
                throw StoreFailure(message: "读取会话失败：\(String(cString: sqlite3_errmsg(db)))")
            }
            var row: [String: String] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                if let value = sqlite3_column_text(statement, column) {
                    row[name] = String(cString: value)
                }
            }
            result.append(row)
        }
    }
}

/// Adapter for the local SQLite layout observed in ChatGPT/Codex 26.1021.
/// This is a version-sensitive local integration, not a public desktop API.
final class LocalSessionStore {
    let root: URL
    private let rollouts = RolloutTailer()

    init(root: URL? = nil) {
        self.root = root ?? URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path)
    }

    func scan(retaining ids: [String] = [], finishedSince: Date? = nil, now: Date = Date()) throws -> [Session] {
        let metadata = try ReadOnlyDatabase(url: root.appendingPathComponent("state_5.sqlite"))
        let history = try ReadOnlyDatabase(url: root.appendingPathComponent("thread_history_1.sqlite"))
        // A hard allowlist avoids reading reasoning, prompts, tool arguments or tool output.
        var rows = try metadata.rows("""
            SELECT id, COALESCE(NULLIF(name, ''), title) AS title, source, archived, rollout_path,
                   COALESCE(updated_at_ms / 1000.0, updated_at) AS updated
            FROM threads WHERE archived = 0 AND source NOT LIKE '%"subagent"%'
            ORDER BY updated_at DESC LIMIT 160
            """)
        let found = Set(rows.compactMap { $0["id"] })
        for id in ids where !found.contains(id) {
            rows += try metadata.rows("""
                SELECT id, COALESCE(NULLIF(name, ''), title) AS title, source, archived, rollout_path,
                       COALESCE(updated_at_ms / 1000.0, updated_at) AS updated
                FROM threads WHERE id = ? AND source NOT LIKE '%"subagent"%'
                """, bindings: [id])
        }
        var sessions: [Session] = []
        let retained = Set(ids)
        for row in rows {
            guard let id = row["id"] else { continue }
            let turn = try history.rows("""
                SELECT turn_id, status, started_at, completed_at FROM thread_turns
                WHERE thread_id = ? ORDER BY rollout_ordinal DESC LIMIT 1
                """, bindings: [id]).first
            let title = compactText(row["title"] ?? "未命名会话", limit: 100)
            let recentlyUpdated = now.timeIntervalSince1970 - (Double(row["updated"] ?? "0") ?? 0) < 86400
            if recentlyUpdated || retained.contains(id),
               let live = rollouts.read(row["rollout_path"] ?? ""),
               var session = live.session(id: id, title: title, archived: row["archived"] == "1", now: now) {
                let indexedStart = Double(turn?["started_at"] ?? "0") ?? 0
                if session.startedAt == nil, session.turnID == turn?["turn_id"], indexedStart > 0 {
                    session.startedAt = Date(timeIntervalSince1970: indexedStart)
                }
                let differentNewTurn = session.turnID != turn?["turn_id"] && session.updatedAt.timeIntervalSince1970 >= indexedStart
                let indexedTerminal = ["completed", "failed", "interrupted"].contains(turn?["status"] ?? "")
                // The history projection can lag by many turns after resume, or
                // still refer to the old file when the live rollout was split.
                if turn == nil || differentNewTurn || (session.turnID == turn?["turn_id"] && (!indexedTerminal || live.explicitLifecycle && session.status.isTerminal)) {
                    if !session.status.isTerminal || retained.contains(id) || (finishedSince.map { session.updatedAt >= $0 } ?? false) {
                        sessions.append(session)
                    }
                    continue
                }
            }
            guard let turn, let turnID = turn["turn_id"] else { continue }
            let activity = Date(timeIntervalSince1970: max(
                Double(row["updated"] ?? "0") ?? 0,
                Double(turn["completed_at"] ?? turn["started_at"] ?? "0") ?? 0))
            var status: SessionStatus
            switch turn["status"] {
            case "inProgress": status = now.timeIntervalSince(activity) < 1800 ? .running : .unknown
            case "completed": status = .completed
            case "failed": status = .failed
            case "interrupted": status = .interrupted
            default: status = .unknown
            }
            if status.isTerminal && !retained.contains(id) {
                // Avoid repeatedly parsing old completed histories. Also pick up
                // short turns that start and finish between two polling ticks.
                guard let since = finishedSince,
                      let completed = Double(turn["completed_at"] ?? ""),
                      completed >= since.timeIntervalSince1970 else { continue }
            }
            // Extract only public message text and a small safe subset of tool metadata in SQL.
            // Never fetch an entire item_json: it can include secrets in tool inputs/outputs.
            let items = try history.rows("""
                SELECT item_type,
                    CASE WHEN item_type = 'agentMessage' THEN json_extract(item_json, '$.text') END AS text,
                    CASE WHEN item_type = 'agentMessage' THEN json_extract(item_json, '$.phase') END AS phase,
                    json_extract(item_json, '$.status') AS status,
                    CASE WHEN item_type IN ('mcpToolCall', 'dynamicToolCall')
                         THEN json_extract(item_json, '$.tool') END AS tool
                FROM thread_items WHERE thread_id = ? AND turn_id = ?
                    AND item_type IN ('agentMessage', 'commandExecution', 'mcpToolCall',
                        'dynamicToolCall', 'fileChange', 'webSearch', 'contextCompaction', 'sleep')
                ORDER BY rollout_ordinal DESC LIMIT 12
                """, bindings: [id, turnID])
            if status == .running, let latest = items.first,
               ["waitingForApproval", "waitingForInput", "needsApproval"].contains(latest["status"] ?? "") {
                status = .waiting
            }
            let summary = Self.summarize(items, status: status)
            sessions.append(Session(id: id, turnID: turnID, title: compactText(row["title"] ?? "未命名会话", limit: 100),
                                    status: status, summary: summary, updatedAt: activity,
                                    archived: row["archived"] == "1",
                                    startedAt: Double(turn["started_at"] ?? "").flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }))
        }
        return sessions
    }

    static func summarize(_ items: [[String: String]], status: SessionStatus) -> String {
        let messages = items.filter { $0["item_type"] == "agentMessage" }
        let commentary = messages.first { $0["phase"] == "commentary" && !($0["text"] ?? "").isEmpty }
        let final = messages.first { $0["phase"] == "final_answer" && !($0["text"] ?? "").isEmpty }
        if status.isTerminal {
            return compactText(final?["text"] ?? commentary?["text"] ?? "点击打开会话，查看结果")
        }
        if status == .unknown { return "记录长时间未更新，请打开会话核实" }
        let latest = items.first
        let operation: String?
        switch latest?["item_type"] {
        case "commandExecution": operation = latest?["status"] == "inProgress" ? "正在执行命令" : "处理命令结果"
        case "mcpToolCall", "dynamicToolCall": operation = "调用工具 \(compactText(latest?["tool"] ?? "", limit: 64))"
        case "fileChange": operation = "正在修改文件"
        case "webSearch": operation = "正在检索资料"
        case "contextCompaction": operation = "正在整理上下文"
        case "sleep": operation = "等待下一步"
        default: operation = nil
        }
        if let text = commentary?["text"] {
            return compactText([operation, text].compactMap { $0 }.joined(separator: " · "))
        }
        return operation ?? "正在处理，等待公开进度更新"
    }
}
