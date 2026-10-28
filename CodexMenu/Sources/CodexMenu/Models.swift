import Foundation

enum SessionStatus: String, Codable {
    case running, completed, failed, interrupted, waiting, unknown

    var label: String {
        switch self {
        case .running: return "运行中"
        case .completed: return "已完成"
        case .failed: return "出错了"
        case .interrupted: return "已中断"
        case .waiting: return "等待操作"
        case .unknown: return "状态待核实"
        }
    }

    var symbol: String {
        switch self {
        case .running: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .interrupted: return "pause.circle.fill"
        case .waiting: return "hand.raised.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var isTerminal: Bool { [.completed, .failed, .interrupted].contains(self) }
}

struct Session: Codable, Equatable, Identifiable {
    let id: String
    var turnID: String
    var title: String
    var status: SessionStatus
    var summary: String
    var updatedAt: Date
    var archived: Bool = false
    var startedAt: Date? = nil

    var displayText: String { "\(status.label) · \(summary)" }
}

struct MenuPreferences: Codable, Equatable {
    // Match the graphite tile and light ink in the bundled app icon.
    static let defaultBackgroundHex: UInt32 = 0x3C434E
    static let defaultTextHex: UInt32 = 0xF7F8FA
    var cardWidth: Double = 240
    var maxVisible: Int = 3
    var scrolling: Bool = true
    var menuFontSize: Double = 11
    var detailFontSize: Double = 13
    var scrollSpeed: Double = 24
    var showTitle: Bool = true
    var showElapsed: Bool = true
    var animateLamps: Bool = true
    var customColors: Bool = false
    var backgroundHex: UInt32 = Self.defaultBackgroundHex
    var textHex: UInt32 = Self.defaultTextHex
    var backgroundOpacity: Double = 1

    init() {}

    private enum CodingKeys: String, CodingKey {
        case cardWidth, maxVisible, scrolling, menuFontSize, detailFontSize, scrollSpeed
        case showTitle, showElapsed, animateLamps
        case customColors, backgroundHex, textHex, backgroundOpacity
    }

    // Older state files contain only width/count/scrolling. New controls must
    // gain defaults without losing retained conversations or acknowledged turns.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        cardWidth = try values.decodeIfPresent(Double.self, forKey: .cardWidth) ?? 240
        maxVisible = try values.decodeIfPresent(Int.self, forKey: .maxVisible) ?? 3
        scrolling = try values.decodeIfPresent(Bool.self, forKey: .scrolling) ?? true
        menuFontSize = try values.decodeIfPresent(Double.self, forKey: .menuFontSize) ?? 11
        detailFontSize = try values.decodeIfPresent(Double.self, forKey: .detailFontSize) ?? 13
        scrollSpeed = try values.decodeIfPresent(Double.self, forKey: .scrollSpeed) ?? 24
        showTitle = try values.decodeIfPresent(Bool.self, forKey: .showTitle) ?? true
        showElapsed = try values.decodeIfPresent(Bool.self, forKey: .showElapsed) ?? true
        animateLamps = try values.decodeIfPresent(Bool.self, forKey: .animateLamps) ?? true
        // Retired theme/cutout keys are ignored. Built-in colors always use
        // opaque graphite, while explicitly customized colors remain intact.
        customColors = try values.decodeIfPresent(Bool.self, forKey: .customColors) ?? false
        backgroundHex = try values.decodeIfPresent(UInt32.self, forKey: .backgroundHex) ?? Self.defaultBackgroundHex
        textHex = try values.decodeIfPresent(UInt32.self, forKey: .textHex) ?? Self.defaultTextHex
        backgroundOpacity = try values.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 1
        if !customColors {
            backgroundHex = Self.defaultBackgroundHex
            textHex = Self.defaultTextHex
            backgroundOpacity = 1
        }
        self = normalized
    }

    var normalized: MenuPreferences {
        var value = self
        value.cardWidth = cardWidth.isFinite ? min(480, max(180, cardWidth)) : 240
        value.maxVisible = min(6, max(1, maxVisible))
        value.menuFontSize = menuFontSize.isFinite ? min(15, max(10, menuFontSize)) : 11
        value.detailFontSize = detailFontSize.isFinite ? min(20, max(11, detailFontSize)) : 13
        value.scrollSpeed = scrollSpeed.isFinite ? min(60, max(12, scrollSpeed)) : 24
        value.backgroundHex = backgroundHex & 0xFFFFFF
        value.textHex = textHex & 0xFFFFFF
        value.backgroundOpacity = backgroundOpacity.isFinite ? min(1, max(0, backgroundOpacity)) : 1
        return value
    }
}

struct SavedState: Codable {
    var preferences = MenuPreferences()
    var sessions: [String: Session] = [:]
    // Acknowledge a turn, not a thread: a new turn must appear again.
    var acknowledged: [String: String] = [:]
}

struct SessionTracker {
    var state: SavedState
    var startedAt = Date()

    var ordered: [Session] {
        state.sessions.values.sorted {
            // Give live work the limited menu-bar space; completed cards remain
            // accessible in the overflow menu until the user opens them.
            let firstLive = !$0.status.isTerminal
            let secondLive = !$1.status.isTerminal
            if firstLive != secondLive { return firstLive }
            // Keep a stable order when progress messages update.
            if $0.id != $1.id { return $0.id < $1.id }
            return $0.turnID < $1.turnID
        }
    }

    mutating func ingest(_ snapshots: [Session]) {
        for session in snapshots {
            if session.archived {
                state.sessions.removeValue(forKey: session.id)
                continue
            }
            if state.acknowledged[session.id] == session.turnID {
                state.sessions.removeValue(forKey: session.id)
                continue
            }
            // Do not flood the bar with old completed conversations at startup.
            // Once observed running, a conversation stays until it is opened.
            let justFinished = session.status.isTerminal && session.updatedAt >= startedAt
            if state.sessions[session.id] != nil || [.running, .waiting].contains(session.status) || justFinished {
                state.sessions[session.id] = session
            }
        }
    }

    mutating func acknowledge(_ session: Session) {
        guard session.status.isTerminal else { return }
        state.acknowledged[session.id] = session.turnID
        // Navigation completes asynchronously. A new turn may have started
        // since the user clicked the previously completed turn.
        if state.sessions[session.id]?.turnID == session.turnID {
            state.sessions.removeValue(forKey: session.id)
        }
    }
}

final class StatePersistence {
    let url: URL

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexMenu/state.json")
    }

    func load() throws -> SavedState {
        guard FileManager.default.fileExists(atPath: url.path) else { return SavedState() }
        return try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
    }

    func save(_ state: SavedState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}

func compactText(_ value: String, limit: Int = 600) -> String {
    let plain = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return plain.count > limit ? String(plain.prefix(limit)) + "…" : plain
}
