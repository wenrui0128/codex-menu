import AppKit

/// Use the system status item's own button and action dispatch. Each icon has
/// its own NSStatusItem; no custom shared view routes events between sessions.
final class NativeMenuBarItem: NSObject {
    let statusItem: NSStatusItem
    let button: NSStatusBarButton
    var onPrimaryClick: (() -> Void)?
    var onSecondaryClick: ((NSEvent) -> Void)?
    private var removed = false

    init(width: CGFloat, autosaveName: String) {
        statusItem = NSStatusBar.system.statusItem(withLength: width)
        button = statusItem.button!
        super.init()
        statusItem.autosaveName = autosaveName
        button.target = self
        button.action = #selector(activate(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    deinit { remove() }

    func remove() {
        guard !removed else { return }
        removed = true
        button.target = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func activate(_ sender: NSStatusBarButton) {
        guard sender === button, !removed else { return }
        if let event = NSApp.currentEvent, event.window === button.window,
           event.type == .rightMouseUp || event.type == .leftMouseUp && event.modifierFlags.contains(.control) {
            // Let the native button finish tracking before showing a transient
            // preview or starting a native menu's event loop.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.removed else { return }
                self.onSecondaryClick?(event)
            }
        } else {
            onPrimaryClick?()
        }
    }
}

/// A stable native status item and action target for exactly one conversation.
final class SessionMenuItem {
    private let native: NativeMenuBarItem
    var statusItem: NSStatusItem { native.statusItem }
    var button: NSStatusBarButton { native.button }
    let badge: SessionBadgeView
    private(set) var session: Session
    var onOpen: ((Session) -> Void)?
    var onContextMenu: ((Session, NSEvent, NSView) -> Void)?

    init(session: Session, width: CGFloat) {
        self.session = session
        native = NativeMenuBarItem(width: width, autosaveName: "CodexMenu.session.\(session.id)")
        badge = SessionBadgeView(session: session, width: width, height: NSStatusBar.system.thickness)
        button.identifier = NSUserInterfaceItemIdentifier("CodexMenu.session.\(session.id)")
        native.onPrimaryClick = { [weak self] in
            guard let self else { return }
            self.onOpen?(self.session)
        }
        native.onSecondaryClick = { [weak self] event in
            guard let self else { return }
            self.onContextMenu?(self.session, event, self.button)
        }
        badge.frame = button.bounds
        badge.autoresizingMask = [.width, .height]
        button.addSubview(badge)
        update(session, width: width, scrolling: true)
    }

    func remove() { native.remove() }

    func update(_ value: Session, width: CGFloat, scrolling: Bool, preferences: MenuPreferences? = nil) {
        precondition(value.id == session.id, "A status item cannot change conversations")
        session = value
        if statusItem.length != width { statusItem.length = width }
        badge.update(value)
        if let preferences { badge.apply(preferences) }
        badge.scrolling = scrolling
        badge.frame = button.bounds
        button.toolTip = badge.toolTip
        button.setAccessibilityLabel("\(value.title)，\(value.displayText)")
        button.setAccessibilityHelp(value.status.isTerminal ? "打开会话并收起此条目；右键预览进度" : "打开会话，保留此条目；右键预览进度")
    }
}

struct StatusItemLayout {
    static let controlWidth: CGFloat = 44
    static let spacing: CGFloat = 8
    let cardWidth: CGFloat
    let visibleCount: Int

    init(sessions: Int, preferences: MenuPreferences, budget: CGFloat) {
        let preferences = preferences.normalized
        let available = max(0, budget - Self.controlWidth)
        cardWidth = CGFloat(preferences.cardWidth)
        let capacity = Int(available / (cardWidth + Self.spacing))
        visibleCount = min(max(0, sessions), preferences.maxVisible, capacity)
    }
}

final class StatusItems {
    let control = NativeMenuBarItem(width: StatusItemLayout.controlWidth, autosaveName: "CodexMenu.control")
    private(set) var items: [String: SessionMenuItem] = [:]
    private(set) var orderedItems: [SessionMenuItem] = []
    var onOpen: ((Session) -> Void)?
    var onContextMenu: ((Session, NSEvent, NSView) -> Void)?
    var onShowAll: (() -> Void)?

    init() {
        control.button.font = .systemFont(ofSize: 10, weight: .medium)
        control.button.imagePosition = .imageLeading
        control.button.setAccessibilityLabel("Codex Menu 全部会话与设置")
        control.onPrimaryClick = { [weak self] in self?.onShowAll?() }
        control.onSecondaryClick = { [weak self] _ in self?.onShowAll?() }
        update([], width: 240, preferences: MenuPreferences(), hiddenCount: 0, readError: nil)
    }

    deinit { remove() }

    func update(_ sessions: [Session], width: CGFloat, preferences: MenuPreferences, hiddenCount: Int, readError: String?) {
        let keep = Set(sessions.map(\.id))
        for id in Array(items.keys) where !keep.contains(id) { items.removeValue(forKey: id)?.remove() }
        orderedItems = sessions.map { session in
            let item: SessionMenuItem
            if let existing = items[session.id] { item = existing }
            else {
                item = SessionMenuItem(session: session, width: width)
                item.onOpen = { [weak self] in self?.onOpen?($0) }
                item.onContextMenu = { [weak self] in self?.onContextMenu?($0, $1, $2) }
                items[session.id] = item
            }
            item.update(session, width: width, scrolling: preferences.scrolling && readError == nil, preferences: preferences)
            item.badge.lamp.update(session.status, motionAllowed: readError == nil && preferences.animateLamps)
            if let readError {
                item.button.toolTip = "数据读取失败；以下是最后一次记录，当前状态尚未确认。\n\(readError)\n\(session.title)\n\(session.summary)"
            }
            return item
        }
        control.button.title = hiddenCount > 0 ? "+\(hiddenCount)" : ""
        control.button.image = AppArtwork.controlIcon(hasReadError: readError != nil)
        control.button.toolTip = readError.map { "数据读取失败：\($0)\n点击查看详情" }
            ?? "\(sessions.count + hiddenCount) 个保留的会话\n左键或右键查看全部会话和设置\n按住 ⌘ 拖动可调整各个图标的位置"
    }

    func remove() {
        for item in items.values { item.remove() }
        items.removeAll()
        orderedItems.removeAll()
        control.remove()
    }
}

enum StatusMenuPresentation {
    static func show(_ menu: NSMenu, from anchor: NSView) {
        guard anchor.window != nil else { return }
        let y = anchor.isFlipped ? anchor.bounds.maxY + 4 : anchor.bounds.minY - 4
        menu.popUp(positioning: nil, at: NSPoint(x: anchor.bounds.minX, y: y), in: anchor)
    }
}
