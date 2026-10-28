import AppKit

/// Uses native NSMenuItems so pointer, keyboard and VoiceOver share one action.
enum SessionMenuPresentation {
    static func group(for status: SessionStatus) -> String {
        switch status {
        case .waiting, .failed: return "需要操作"
        case .running: return "正在进行"
        case .completed, .interrupted, .unknown: return "已完成与保留"
        }
    }

    static func elapsed(_ session: Session, now: Date = Date()) -> String? {
        guard [.running, .waiting].contains(session.status), let start = session.startedAt,
              start.timeIntervalSince1970 > 0, start <= now else { return nil }
        let seconds = Int(min(now.timeIntervalSince(start), 365 * 86400))
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func title(for session: Session, preferences: MenuPreferences, now: Date = Date()) -> NSAttributedString {
        let size = CGFloat(preferences.detailFontSize)
        let font = NSFont.menuFont(ofSize: size)
        let timer = preferences.showElapsed ? elapsed(session, now: now).map { "  \($0)" } ?? "" : ""
        let suffix = "\(timer)  ·  \(session.status.label)"
        let suffixWidth = (suffix as NSString).size(withAttributes: [.font: font]).width
        let titleBudget = max(100, 370 - suffixWidth)
        let label = truncated(session.title, font: font, width: titleBudget)
        let result = NSMutableAttributedString(string: label, attributes: [.font: font])
        if !timer.isEmpty {
            result.append(NSAttributedString(string: timer, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: max(11, size - 1), weight: .regular)]))
        }
        // Leave colors to NSMenu so selected text remains readable in both themes.
        result.append(NSAttributedString(string: "  ·  \(session.status.label)", attributes: [.font: NSFont.menuFont(ofSize: max(11, size - 1))]))
        return result
    }

    private static func truncated(_ text: String, font: NSFont, width: CGFloat) -> String {
        if (text as NSString).size(withAttributes: [.font: font]).width <= width { return text }
        var result = text
        while !result.isEmpty && ((result + "…") as NSString).size(withAttributes: [.font: font]).width > width { result.removeLast() }
        return result + "…"
    }
}
