import XCTest
import SQLite3
@testable import CodexMenu

final class RolloutTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2000000020)

    private func event(_ type: String, turn: String = "live", extra: [String: Any] = [:]) throws -> Data {
        var payload: [String: Any] = ["type": type, "turn_id": turn]
        payload.merge(extra) { _, new in new }
        var data = try JSONSerialization.data(withJSONObject: ["timestamp": "2033-05-18T03:33:30Z", "type": "event_msg", "payload": payload])
        data.append(10)
        return data
    }

    private func database(_ url: URL, sql: String) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }

    private func folder() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: path) }
        return path
    }

    func testActiveRolloutOverridesStaleCompletedIndexAndThenCompletes() throws {
        let root = try folder(), path = root.appendingPathComponent("resumed.jsonl")
        var log = try event("task_started")
        log += try event("item_completed", extra: ["item": ["type": "AgentMessage", "phase": "commentary", "content": ["正在检查运行中的会话"]]])
        log += try event("item_completed", extra: ["item": ["type": "Reasoning", "raw_content": ["PRIVATE_REASONING"], "summary_text": ["PRIVATE_SUMMARY"]]])
        log += try event("item_completed", extra: ["item": ["type": "CommandExecution", "status": "InProgress", "command": "SECRET_INPUT", "aggregated_output": "SECRET_OUTPUT"]])
        try log.write(to: path)
        try database(root.appendingPathComponent("state_5.sqlite"), sql: """
            CREATE TABLE threads(id TEXT, name TEXT, title TEXT, source TEXT, archived INTEGER, updated_at_ms INTEGER, updated_at INTEGER, rollout_path TEXT);
            INSERT INTO threads VALUES ('real', NULL, '恢复的会话', 'vscode', 0, 2000000010000, 2000000010, '\(path.path)');
            """)
        try database(root.appendingPathComponent("thread_history_1.sqlite"), sql: """
            CREATE TABLE thread_turns(thread_id TEXT, turn_id TEXT, rollout_ordinal INTEGER, status TEXT, started_at INTEGER, completed_at INTEGER);
            CREATE TABLE thread_items(thread_id TEXT, turn_id TEXT, rollout_ordinal INTEGER, item_type TEXT, item_json TEXT);
            INSERT INTO thread_turns VALUES ('real', 'old', 0, 'completed', 1999999000, 1999999010);
            """)
        let store = LocalSessionStore(root: root)
        let active = try XCTUnwrap(try store.scan(now: now).first)
        XCTAssertEqual(active.turnID, "live")
        XCTAssertEqual(active.status, .running)
        XCTAssertEqual(active.startedAt, ISO8601DateFormatter().date(from: "2033-05-18T03:33:30Z"))
        XCTAssertTrue(active.summary.contains("正在检查运行中的会话"))
        XCTAssertFalse(active.summary.contains("PRIVATE"))
        XCTAssertFalse(active.summary.contains("SECRET"))
        let handle = try FileHandle(forWritingTo: path)
        try handle.seekToEnd()
        try handle.write(contentsOf: event("task_complete", extra: ["last_agent_message": "已完成检查"]))
        try handle.close()
        let done = try XCTUnwrap(try store.scan(retaining: ["real"], now: now).first)
        XCTAssertEqual(done.status, .completed)
        XCTAssertEqual(done.summary, "已完成检查")
    }

    func testIncrementalPartialLinesAndNewSplitFile() throws {
        let root = try folder(), path = root.appendingPathComponent("one.jsonl")
        let complete = try event("task_started", turn: "first")
        try Data(complete.dropLast(5)).write(to: path)
        let tailer = RolloutTailer()
        XCTAssertNil(tailer.read(path.path)?.turnID)
        let handle = try FileHandle(forWritingTo: path)
        try handle.seekToEnd(); try handle.write(contentsOf: Data(complete.suffix(5))); try handle.close()
        XCTAssertEqual(tailer.read(path.path)?.turnID, "first")
        let split = root.appendingPathComponent("two.jsonl")
        try event("task_started", turn: "resumed").write(to: split)
        XCTAssertEqual(tailer.read(split.path)?.turnID, "resumed")
        XCTAssertEqual(tailer.read(split.path)?.status, .running)
    }

    func testLargeTailCanIdentifyCurrentTurnWithoutItsStartMarker() throws {
        let root = try folder(), path = root.appendingPathComponent("large.jsonl")
        var log = try event("task_started")
        log += Data(repeating: 32, count: 3 * 1024 * 1024)
        log.append(10)
        log += try event("item_completed", extra: ["item": ["type": "Reasoning", "raw_content": "PRIVATE"]])
        try log.write(to: path)
        let live = try XCTUnwrap(RolloutTailer().read(path.path))
        XCTAssertEqual(live.turnID, "live")
        XCTAssertEqual(live.status, .running)
        XCTAssertTrue(live.items.isEmpty)
        XCTAssertNil(live.startedAt, "A bounded tail without task_started must not invent a timer")
    }
}
