import XCTest
import SQLite3
@testable import CodexMenu

final class SessionTests: XCTestCase {
    private func session(_ id: String, turn: String = "one", status: SessionStatus) -> Session {
        Session(id: id, turnID: turn, title: "示例会话", status: status, summary: "公开进度", updatedAt: Date())
    }

    func testCompletionStaysUntilOpenedAndOnlyThatCardIsRemoved() {
        var tracker = SessionTracker(state: SavedState())
        let a = session("a", status: .running), b = session("b", status: .running)
        tracker.ingest([a, b])
        let done = session("a", status: .completed)
        tracker.ingest([done, b])
        XCTAssertEqual(tracker.ordered.count, 2)
        tracker.acknowledge(done)
        XCTAssertEqual(tracker.ordered.map(\.id), ["b"])
        tracker.ingest([done, b])
        XCTAssertEqual(tracker.ordered.map(\.id), ["b"])
    }

    func testNewTurnReappearsAndOpeningRunningCardKeepsIt() {
        var tracker = SessionTracker(state: SavedState())
        tracker.ingest([session("a", status: .running)])
        let done = session("a", status: .completed)
        tracker.acknowledge(done)
        let next = session("a", turn: "two", status: .running)
        tracker.ingest([next])
        tracker.acknowledge(next)
        XCTAssertEqual(tracker.ordered, [next])
    }

    func testNoHistoricalCompletedFloodAndUnknownDoesNotBecomeComplete() {
        var tracker = SessionTracker(state: SavedState())
        var old = session("old", status: .completed)
        old.updatedAt = .distantPast
        tracker.ingest([old])
        XCTAssertTrue(tracker.ordered.isEmpty)
        tracker.ingest([session("live", status: .running)])
        tracker.ingest([session("live", status: .unknown)])
        XCTAssertEqual(tracker.ordered.first?.status, .unknown)
    }

    func testShortTurnCompletedBetweenPollingTicksStillAppears() {
        let start = Date(timeIntervalSince1970: 2000000000)
        var tracker = SessionTracker(state: SavedState(), startedAt: start)
        var done = session("quick", status: .completed)
        done.updatedAt = start.addingTimeInterval(1)
        tracker.ingest([done])
        XCTAssertEqual(tracker.ordered, [done])
    }

    func testPersistenceRetainsCompletionAcrossRestart() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let persistence = StatePersistence(url: folder.appendingPathComponent("state.json"))
        var tracker = SessionTracker(state: SavedState())
        tracker.ingest([session("a", status: .running)])
        tracker.ingest([session("a", status: .completed)])
        try persistence.save(tracker.state)
        let reloaded = SessionTracker(state: try persistence.load())
        XCTAssertEqual(reloaded.ordered.first?.status, .completed)
    }

    private func writeDatabase(_ url: URL, sql: String) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &error)
        if let error { let message = String(cString: error); sqlite3_free(error); XCTFail(message) }
        XCTAssertEqual(result, SQLITE_OK)
    }

    func testStoreReadsLatestTurnExcludesReasoningAndSubagents() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try writeDatabase(folder.appendingPathComponent("state_5.sqlite"), sql: """
            CREATE TABLE threads(id TEXT, name TEXT, title TEXT, source TEXT, archived INTEGER, updated_at_ms INTEGER, updated_at INTEGER, rollout_path TEXT);
            INSERT INTO threads VALUES ('real', '真实标题', '旧标题', 'vscode', 0, 2000000000000, 2000000000, '');
            INSERT INTO threads VALUES ('agent', NULL, '子代理', '{"subagent":{}}', 0, 2000000000000, 2000000000, '');
            """)
        try writeDatabase(folder.appendingPathComponent("thread_history_1.sqlite"), sql: """
            CREATE TABLE thread_turns(thread_id TEXT, turn_id TEXT, rollout_ordinal INTEGER, status TEXT, started_at INTEGER, completed_at INTEGER);
            CREATE TABLE thread_items(thread_id TEXT, turn_id TEXT, rollout_ordinal INTEGER, item_type TEXT, item_json TEXT);
            INSERT INTO thread_turns VALUES ('real', 'old', 0, 'completed', 1999999000, 1999999010);
            INSERT INTO thread_turns VALUES ('real', 'new', 10, 'inProgress', 2000000000, NULL);
            INSERT INTO thread_turns VALUES ('agent', 'one', 0, 'inProgress', 2000000000, NULL);
            INSERT INTO thread_items VALUES ('real', 'new', 11, 'agentMessage', '{"text":"正在检查公开资料","phase":"commentary"}');
            INSERT INTO thread_items VALUES ('real', 'new', 12, 'commandExecution', '{"status":"inProgress","command":"SECRET_COMMAND","aggregatedOutput":"SECRET_OUTPUT"}');
            INSERT INTO thread_items VALUES ('real', 'new', 13, 'reasoning', '{"text":"PRIVATE_REASONING"}');
            """)
        let store = LocalSessionStore(root: folder)
        let sessions = try store.scan(now: Date(timeIntervalSince1970: 2000000010))
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].title, "真实标题")
        XCTAssertEqual(sessions[0].turnID, "new")
        XCTAssertEqual(sessions[0].status, .running)
        XCTAssertEqual(sessions[0].startedAt, Date(timeIntervalSince1970: 2000000000))
        XCTAssertTrue(sessions[0].summary.contains("正在检查公开资料"))
        XCTAssertFalse(sessions[0].summary.contains("PRIVATE"))
        XCTAssertFalse(sessions[0].summary.contains("SECRET"))
        let stale = try store.scan(now: Date(timeIntervalSince1970: 2000002000))
        XCTAssertEqual(stale[0].status, .unknown)
        let db = try ReadOnlyDatabase(url: folder.appendingPathComponent("state_5.sqlite"))
        XCTAssertThrowsError(try db.rows("DELETE FROM threads"))
    }
}
