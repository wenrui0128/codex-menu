import Foundation

/// Decodes only lifecycle identifiers and public progress. Reasoning, prompts,
/// tool arguments and outputs are never decoded into the application model.
private struct PublicRolloutEvent: Decodable {
    var timestamp: Date?
    var turnID: String?
    var lifecycle: SessionStatus?
    var item: [String: String]?

    private enum Key: String, CodingKey {
        case type, timestamp, payload, turn_id, item, last_agent_message, error
        case phase, text, content, status, tool
    }

    private struct TextBlock: Decodable { let text: String? }

    init(from decoder: Decoder) throws {
        let envelope = try decoder.container(keyedBy: Key.self)
        guard let kind = try envelope.decodeIfPresent(String.self, forKey: .type),
              ["event_msg", "turn_context", "token_usage_record"].contains(kind) else { return }
        if let raw = try envelope.decodeIfPresent(String.self, forKey: .timestamp) {
            timestamp = Self.fractional.date(from: raw) ?? Self.whole.date(from: raw)
        }
        let payload = try envelope.nestedContainer(keyedBy: Key.self, forKey: .payload)
        turnID = try payload.decodeIfPresent(String.self, forKey: .turn_id)
        guard kind == "event_msg" else { return }
        switch try payload.decodeIfPresent(String.self, forKey: .type) {
        case "task_started": lifecycle = .running
        case "task_complete":
            if payload.contains(.error), try !payload.decodeNil(forKey: .error) { lifecycle = .failed }
            else { lifecycle = .completed }
            if let text = try payload.decodeIfPresent(String.self, forKey: .last_agent_message), !text.isEmpty {
                item = ["item_type": "agentMessage", "phase": "final_answer", "text": compactText(text)]
            }
        case "turn_aborted", "task_aborted": lifecycle = .interrupted
        case "task_failed": lifecycle = .failed
        case "item_completed", "item_started":
            let body = try payload.nestedContainer(keyedBy: Key.self, forKey: .item)
            let type = (try body.decodeIfPresent(String.self, forKey: .type) ?? "").lowercased()
            switch type {
            case "agentmessage":
                let phase = try body.decodeIfPresent(String.self, forKey: .phase) ?? ""
                guard ["commentary", "final_answer"].contains(phase) else { return }
                let text: String
                if let value = try body.decodeIfPresent(String.self, forKey: .text) { text = value }
                else if let parts = try? body.decode([String].self, forKey: .content) { text = parts.joined(separator: " ") }
                else if let parts = try? body.decode([TextBlock].self, forKey: .content) { text = parts.compactMap(\.text).joined(separator: " ") }
                else { return }
                item = ["item_type": "agentMessage", "phase": phase, "text": compactText(text)]
            case "commandexecution", "filechange", "mcptoolcall", "dynamictoolcall", "websearch", "contextcompaction":
                let types = ["commandexecution": "commandExecution", "filechange": "fileChange",
                             "mcptoolcall": "mcpToolCall", "dynamictoolcall": "dynamicToolCall",
                             "websearch": "webSearch", "contextcompaction": "contextCompaction"]
                var safe = ["item_type": types[type]!]
                if let status = try body.decodeIfPresent(String.self, forKey: .status) {
                    safe["status"] = status.lowercased() == "inprogress" ? "inProgress" : status
                }
                if type == "mcptoolcall" || type == "dynamictoolcall",
                   let tool = try body.decodeIfPresent(String.self, forKey: .tool) { safe["tool"] = compactText(tool, limit: 64) }
                item = safe
            default: break
            }
        default: break
        }
    }

    private static let fractional: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return value
    }()
    private static let whole = ISO8601DateFormatter()
}

struct LiveRollout {
    var turnID: String?
    var status: SessionStatus = .unknown
    var updatedAt = Date.distantPast
    var startedAt: Date?
    var explicitLifecycle = false
    var items: [[String: String]] = []

    func session(id: String, title: String, archived: Bool, now: Date) -> Session? {
        guard let turnID else { return nil }
        let effective = status == .running && now.timeIntervalSince(updatedAt) >= 1800 ? SessionStatus.unknown : status
        return Session(id: id, turnID: turnID, title: title, status: effective,
                       summary: LocalSessionStore.summarize(items, status: effective), updatedAt: updatedAt,
                       archived: archived, startedAt: startedAt)
    }
}

final class RolloutTailer {
    private struct Cursor {
        var offset: UInt64 = 0
        var droppingLine = false
        var live = LiveRollout()
    }
    private var cursors: [String: Cursor] = [:]
    private let chunkSize = 2 * 1024 * 1024

    func read(_ path: String) -> LiveRollout? {
        guard !path.isEmpty, let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let bytes = attributes[.size] as? NSNumber,
              let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = bytes.uint64Value
        var cursor = cursors[path] ?? Cursor()
        if size < cursor.offset { cursor = Cursor() }
        // A resumed chat may point to a new/split rollout. Read a bounded tail on
        // first access, then only appended bytes; never scan a 300 MB chat each tick.
        if (cursor.offset == 0 || size - cursor.offset > UInt64(chunkSize * 4)) && size > UInt64(chunkSize) {
            cursor.offset = size - UInt64(chunkSize)
            cursor.droppingLine = true
        }
        guard size > cursor.offset else { return cursor.live }
        do {
            try handle.seek(toOffset: cursor.offset)
            guard let data = try handle.read(upToCount: chunkSize), !data.isEmpty else { return cursor.live }
            var start = data.startIndex
            let decoder = JSONDecoder()
            while let newline = data[start...].firstIndex(of: 10) {
                let line = data[start..<newline]
                if cursor.droppingLine { cursor.droppingLine = false }
                else if let event = try? decoder.decode(PublicRolloutEvent.self, from: Data(line)) {
                    if let turn = event.turnID {
                        if cursor.live.turnID != turn {
                            cursor.live = LiveRollout(turnID: turn, status: .running)
                        }
                        if let timestamp = event.timestamp { cursor.live.updatedAt = max(cursor.live.updatedAt, timestamp) }
                        if let lifecycle = event.lifecycle {
                            cursor.live.status = lifecycle
                            cursor.live.explicitLifecycle = true
                            if lifecycle == .running, cursor.live.startedAt == nil { cursor.live.startedAt = event.timestamp }
                        }
                        if let item = event.item {
                            cursor.live.items.insert(item, at: 0)
                            cursor.live.items = Array(cursor.live.items.prefix(12))
                        }
                    }
                }
                start = data.index(after: newline)
            }
            cursor.offset += UInt64(start)
            if start == 0 && data.count == chunkSize {
                // Skip oversized tool-output lines without retaining their body.
                cursor.offset += UInt64(data.count)
                cursor.droppingLine = true
            }
            cursors[path] = cursor
            return cursor.live
        } catch { return nil }
    }
}
