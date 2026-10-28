import AppKit

final class SessionBadgeView: NSView {
    var session: Session
    var scrolling = true
    private(set) var preferences = MenuPreferences()
    let lamp: StatusLampView
    private var hovered = false
    private var tracking: NSTrackingArea?
    private var epoch = ProcessInfo.processInfo.systemUptime
    override var isFlipped: Bool { true }

    init(session: Session, width: CGFloat, height: CGFloat) {
        self.session = session
        lamp = StatusLampView(status: session.status)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        setAccessibilityElement(false)
        addSubview(lamp)
        update(session)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(_ preferences: MenuPreferences) {
        let next = preferences.normalized
        if next != self.preferences { epoch = ProcessInfo.processInfo.systemUptime }
        self.preferences = next
        scrolling = next.scrolling
        lamp.update(session.status, motionAllowed: next.animateLamps)
        needsDisplay = true
    }

    // This view draws progress without intercepting the native button's events.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(_ value: Session) {
        if session.displayText != value.displayText { epoch = ProcessInfo.processInfo.systemUptime }
        session = value
        lamp.update(value.status, motionAllowed: preferences.animateLamps)
        toolTip = "\(value.title)\n\(value.displayText)\n" +
            (value.status.isTerminal ? "点击打开对应会话，并仅收起这一条" : "点击打开对应会话，进度条继续保留")
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; epoch = ProcessInfo.processInfo.systemUptime; needsDisplay = true }

    override func layout() {
        super.layout()
        lamp.frame = NSRect(x: 9, y: bounds.midY - 6, width: 12, height: 12)
    }

    private var textFont: NSFont { .systemFont(ofSize: preferences.menuFontSize) }
    private var titleWidth: CGFloat { min(120, max(58, bounds.width * 0.29)) * CGFloat(preferences.menuFontSize / 11) }
    var progressFrame: NSRect {
        let x = preferences.showTitle ? 47 + min(titleWidth, bounds.width * 0.43) : 27
        return NSRect(x: x, y: 2, width: max(10, bounds.width - x - 12), height: bounds.height - 4)
    }

    var shouldAnimate: Bool {
        scrolling && !hovered && window != nil && !window!.isMiniaturized &&
            window?.firstResponder !== superview &&
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion &&
            NSAttributedString(string: session.displayText, attributes: [.font: textFont]).size().width > progressFrame.width
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let background = MenuPalette.surface(dark: dark)
        let foreground = MenuPalette.foreground(dark: dark)
        let secondary = MenuPalette.secondary(dark: dark)
        let capsule = bounds.insetBy(dx: 1.5, dy: 2)
        let highlighted = (superview as? NSButton)?.isHighlighted ?? false
        let fill = hovered || highlighted ? background.blended(withFraction: 0.07, of: foreground)! : background
        fill.setFill()
        let outline = NSBezierPath(roundedRect: capsule, xRadius: 6, yRadius: 6)
        outline.fill()
        MenuPalette.border(dark: dark).setStroke()
        outline.lineWidth = 0.5
        outline.stroke()

        let titleStyle = NSMutableParagraphStyle()
        titleStyle.lineBreakMode = .byTruncatingTail
        titleStyle.alignment = .left
        let centerY = bounds.midY
        let titleText = NSAttributedString(string: session.title, attributes: [
            .font: NSFont.systemFont(ofSize: preferences.menuFontSize, weight: .medium), .foregroundColor: foreground,
            .paragraphStyle: titleStyle
        ])
        let clip = progressFrame
        if preferences.showTitle {
            titleText.draw(in: NSRect(x: 27, y: centerY - titleText.size().height / 2,
                                     width: clip.minX - 47, height: titleText.size().height))
            MenuPalette.border(dark: dark).setFill()
            NSRect(x: clip.minX - 10, y: centerY - 4, width: 0.5, height: 8).fill()
        }
        let text = NSAttributedString(string: session.displayText, attributes: [
            .font: textFont, .foregroundColor: secondary, .paragraphStyle: titleStyle
        ])
        let textWidth = text.size().width
        var offset: CGFloat = 0
        if shouldAnimate {
            let travel = max(0, textWidth - clip.width)
            let travelTime = Double(travel) / preferences.scrollSpeed
            let phase = (ProcessInfo.processInfo.systemUptime - epoch).truncatingRemainder(dividingBy: travelTime + 4)
            offset = CGFloat(min(max(0, phase - 2), travelTime) * preferences.scrollSpeed)
        }
        NSGraphicsContext.saveGraphicsState()
        clip.clip()
        if shouldAnimate {
            text.draw(at: NSPoint(x: clip.minX - offset, y: centerY - text.size().height / 2))
            if textWidth - offset > clip.width {
                NSGradient(starting: fill.withAlphaComponent(0), ending: fill)?.draw(
                    in: NSRect(x: clip.maxX - 9, y: clip.minY, width: 9, height: clip.height), angle: 0)
            }
        } else {
            text.draw(in: NSRect(x: clip.minX, y: centerY - text.size().height / 2, width: clip.width, height: text.size().height))
        }
        NSGraphicsContext.restoreGraphicsState()
        if superview is NSButton, window?.firstResponder === superview {
            NSGraphicsContext.saveGraphicsState()
            NSFocusRingPlacement.only.set()
            NSBezierPath(roundedRect: capsule, xRadius: 5, yRadius: 5).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

final class MenuAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var menuButton: NSButton!
    private var statusItems: StatusItems!
    private var pollTimer: Timer?
    private var animationTimer: Timer?
    private var menuClock: Timer?
    private var settingsWindow: SettingsWindowController?
    private var controlMenu: NSMenu?
    private var menuIsOpen = false
    private var menuRows: [String: NSMenuItem] = [:]
    private var menuStructure: [String] = []
    private let reader: LocalSessionStore
    private let persistence: StatePersistence
    private let navigator = ThreadNavigator()
    private let detailPopover = SessionPopoverPresenter()
    private var openingThreads = Set<String>()
    private var tracker: SessionTracker
    private var lastSavedData: Data?
    private var busy = false
    private var readError: String?
    private var saveError: String?
    private var lastSynced: Date?
    private var previewMode: Bool
    private var previewStarted = Date()

    init(reader: LocalSessionStore, persistence: StatePersistence, demo: Bool = false, monitoringSince: Date? = nil) {
        self.reader = reader
        self.persistence = persistence
        self.previewMode = demo
        var state = SavedState()
        do { state = try persistence.load() }
        catch { saveError = "无法加载保留的条目：\(error.localizedDescription)" }
        if demo { state = SavedState(); state.sessions = Dictionary(uniqueKeysWithValues: exampleSessions().map { ($0.id, $0) }) }
        tracker = SessionTracker(state: state, startedAt: monitoringSince ?? Date())
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = tracker.state.preferences.theme.appearance
        statusItems = StatusItems()
        menuButton = statusItems.control.button
        statusItems.onShowAll = { [weak self] in self?.showMenu() }
        statusItems.onOpen = { [weak self] in self?.open($0) }
        statusItems.onContextMenu = { [weak self] session, event, view in
            self?.showContextMenu(event: event, view: view, session: session)
        }
        render()
        refresh()
        pollTimer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(pollTimer!, forMode: .common)
        menuClock = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.updateOpenMenu() }
        RunLoop.main.add(menuClock!, forMode: .common)
        animationTimer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            for item in self.statusItems.orderedItems where item.badge.shouldAnimate { item.badge.needsDisplay = true }
        }
        RunLoop.main.add(animationTimer!, forMode: .common)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // Menu bar geometry and contrast can change with the desktop appearance.
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screenChanged), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func screenChanged() { render(); refresh() }

    @objc func refresh() {
        guard !busy else { return }
        if previewMode {
            // Demo data is isolated from actual conversations and is never persisted.
            if Date().timeIntervalSince(previewStarted) > 12,
               var sample = tracker.state.sessions["demo-running"] {
                sample.status = .completed
                sample.summary = "实现与检查已完成，点击此条收起，其他条目保留。"
                tracker.state.sessions[sample.id] = sample
            }
            render()
            return
        }
        busy = true
        let ids = Array(tracker.state.sessions.keys)
        let startedAt = tracker.startedAt
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = Result { try self.reader.scan(retaining: ids, finishedSince: startedAt) }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let sessions):
                    self.readError = nil
                    self.lastSynced = Date()
                    self.tracker.ingest(sessions)
                    self.persist()
                case .failure(let error):
                    self.readError = error.localizedDescription
                }
                self.render()
            }
        }
    }

    private func persist() {
        guard !previewMode else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(tracker.state)
            guard data != lastSavedData else { return }
            try persistence.save(tracker.state)
            lastSavedData = data
            saveError = nil
        } catch { saveError = "无法保存保留的条目：\(error.localizedDescription)" }
    }

    private func render() {
        guard let statusItems else { return }
        let sessions = tracker.ordered
        let preferences = tracker.state.preferences.normalized
        let screen = statusItems.control.button.window?.screen ?? NSScreen.main
        // Keep readable independent items within an estimated space budget;
        // the native menu bar manages each item's final position.
        let region = screen?.auxiliaryTopRightArea?.width ?? ((screen?.frame.width ?? 1440) - 600)
        let budget = max(44, min(900, region - 200))
        let layout = StatusItemLayout(sessions: sessions.count, preferences: preferences, budget: budget)
        statusItems.update(Array(sessions.prefix(layout.visibleCount)), width: layout.cardWidth,
                           preferences: preferences, hiddenCount: sessions.count - layout.visibleCount,
                           readError: readError)
        detailPopover.update(sessions: tracker.state.sessions, readError: readError, preferences: preferences)
        updateOpenMenu()
    }

    private func open(_ session: Session) {
        if previewMode {
            tracker.acknowledge(session)
            render()
            return
        }
        guard openingThreads.insert(session.id).inserted else { return }
        navigator.open(threadID: session.id) { [weak self] result in
            guard let self else { return }
            self.openingThreads.remove(session.id)
            switch result {
            case .success:
                self.tracker.acknowledge(session)
                self.persist()
                self.render()
            case .failure(let error):
                let alert = NSAlert()
                alert.messageText = "暂时无法打开对应会话"
                alert.informativeText = error.localizedDescription + "\n条目会继续保留。"
                alert.runModal()
            }
        }
    }

    @objc private func openFromMenu(_ sender: NSMenuItem) {
        if let session = sender.representedObject as? Session { open(session) }
    }

    @objc private func openCodex() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func info(_ title: String, in menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    @objc private func showMenu() {
        detailPopover.close()
        let menu = buildMenu()
        controlMenu = menu
        StatusMenuPresentation.show(menu, from: menuButton)
    }

    private func showContextMenu(event: NSEvent, view: NSView, session: Session? = nil) {
        guard let session else { showMenu(); return }
        detailPopover.show(session, from: view, readError: readError, preferences: tracker.state.preferences,
                           onOpen: { [weak self] in self?.open($0) },
                           onShowAll: { [weak self] in self?.showMenu() })
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.minimumWidth = 400
        populate(menu)
        return menu
    }

    private var currentMenuStructure: [String] {
        tracker.ordered.map { "\($0.id):\(SessionMenuPresentation.group(for: $0.status))" }
            + [readError ?? "", saveError ?? ""]
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        menuRows.removeAll()
        menuStructure = currentMenuStructure
        let preferences = tracker.state.preferences
        menu.font = .menuFont(ofSize: preferences.detailFontSize)
        let running = tracker.ordered.filter { [.running, .waiting].contains($0.status) }.count
        let header = NSMenuItem()
        header.view = MenuHeaderView(running: running, retained: tracker.ordered.count - running,
                                     demo: previewMode, fontSize: preferences.detailFontSize)
        menu.addItem(header)
        let launch = NSMenuItem(title: "打开 Codex", action: #selector(openCodex), keyEquivalent: "")
        launch.target = self
        launch.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)
        menu.addItem(launch)
        menu.addItem(.separator())
        if tracker.ordered.isEmpty { info("没有运行中的会话，开始任务后会自动显示", in: menu) }
        for group in ["需要操作", "正在进行", "已完成与保留"] {
            let sessions = tracker.ordered.filter { SessionMenuPresentation.group(for: $0.status) == group }
            guard !sessions.isEmpty else { continue }
            info("\(group) · \(sessions.count)", in: menu)
            for session in sessions {
                let item = NSMenuItem(title: "", action: #selector(openFromMenu(_:)), keyEquivalent: "")
                item.target = self
                updateRow(item, session: session)
                menuRows[session.id] = item
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        if let readError { info("读取失败：\(compactText(readError, limit: 70))", in: menu) }
        if let saveError { info(compactText(saveError, limit: 70), in: menu) }
        if let lastSynced {
            let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"
            info("本地会话 · 更新于 \(formatter.string(from: lastSynced))", in: menu)
            menu.items.last?.identifier = NSUserInterfaceItemIdentifier("lastSynced")
        }
        let options = NSMenu()
        for (tag, title, enabled) in [
            (0, "显示会话标题", preferences.showTitle),
            (1, "显示运行计时", preferences.showElapsed),
            (2, "滚动公开进度", preferences.scrolling),
            (3, "状态灯柔和闪烁", preferences.animateLamps)
        ] {
            let item = NSMenuItem(title: title, action: #selector(toggleOption(_:)), keyEquivalent: "")
            item.target = self; item.tag = tag; item.state = enabled ? .on : .off
            options.addItem(item)
        }
        let optionItem = NSMenuItem(title: "选项", action: nil, keyEquivalent: "")
        optionItem.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: nil)
        optionItem.submenu = options
        menu.addItem(optionItem)

        let appearance = NSMenu()
        for theme in MenuTheme.allCases {
            let item = NSMenuItem(title: theme.label, action: #selector(setTheme(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = theme.rawValue
            item.state = preferences.theme == theme ? .on : .off
            appearance.addItem(item)
        }
        appearance.addItem(.separator())
        for (label, sizes, isDetail) in [("菜单栏字号", [10, 11, 12, 13, 14, 15], false),
                                         ("进度卡片字号", [11, 12, 13, 14, 16, 18, 20], true)] {
            let sizesMenu = NSMenu()
            for size in sizes {
                let item = NSMenuItem(title: "\(size) pt", action: #selector(setFontSize(_:)), keyEquivalent: "")
                item.target = self; item.tag = size
                item.representedObject = isDetail
                item.state = (isDetail ? preferences.detailFontSize : preferences.menuFontSize) == Double(size) ? .on : .off
                sizesMenu.addItem(item)
            }
            let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            item.submenu = sizesMenu
            appearance.addItem(item)
        }
        let appearanceItem = NSMenuItem(title: "外观", action: nil, keyEquivalent: "")
        appearanceItem.image = NSImage(systemSymbolName: "textformat.size", accessibilityDescription: nil)
        appearanceItem.submenu = appearance
        menu.addItem(appearanceItem)
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        settings.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        menu.addItem(settings)
        let refresh = NSMenuItem(title: "立即刷新", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        info("Codex Menu · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.5.2")", in: menu)
        menu.addItem(NSMenuItem(title: "退出 Codex Menu", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func updateRow(_ item: NSMenuItem, session: Session) {
        let title = SessionMenuPresentation.title(for: session, preferences: tracker.state.preferences)
        item.title = title.string
        item.attributedTitle = title
        item.representedObject = session
        item.toolTip = "\(session.title)\n\(session.displayText)"
        item.image = StatusLampView.menuImage(for: session.status)
    }

    private func updateOpenMenu() {
        guard menuIsOpen, let menu = controlMenu else { return }
        if menuStructure != currentMenuStructure { populate(menu); return }
        for session in tracker.ordered {
            if let item = menuRows[session.id] { updateRow(item, session: session) }
        }
        if let item = menu.items.first(where: { $0.identifier?.rawValue == "lastSynced" }), let lastSynced {
            let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"
            item.title = "本地会话 · 更新于 \(formatter.string(from: lastSynced))"
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === controlMenu else { return }
        menuIsOpen = true
        updateOpenMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === controlMenu else { return }
        menuIsOpen = false
        controlMenu = nil
        menuRows.removeAll()
    }

    @objc private func toggleOption(_ sender: NSMenuItem) {
        switch sender.tag {
        case 0: tracker.state.preferences.showTitle.toggle()
        case 1: tracker.state.preferences.showElapsed.toggle()
        case 2: tracker.state.preferences.scrolling.toggle()
        case 3: tracker.state.preferences.animateLamps.toggle()
        default: return
        }
        preferencesChanged()
    }

    @objc private func setTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let theme = MenuTheme(rawValue: raw) else { return }
        tracker.state.preferences.theme = theme
        preferencesChanged()
    }

    @objc private func setFontSize(_ sender: NSMenuItem) {
        if sender.representedObject as? Bool == true { tracker.state.preferences.detailFontSize = Double(sender.tag) }
        else { tracker.state.preferences.menuFontSize = Double(sender.tag) }
        preferencesChanged()
    }

    @objc private func showSettings() {
        detailPopover.close()
        controlMenu?.cancelTracking()
        if settingsWindow == nil { settingsWindow = SettingsWindowController(preferences: tracker.state.preferences, demo: previewMode) }
        settingsWindow?.show(preferences: tracker.state.preferences) { [weak self] preferences in
            self?.tracker.state.preferences = preferences
            self?.preferencesChanged()
        }
    }

    private func preferencesChanged() {
        tracker.state.preferences = tracker.state.preferences.normalized
        NSApp.appearance = tracker.state.preferences.theme.appearance
        settingsWindow?.model.replace(tracker.state.preferences, notify: false)
        persist()
        render()
    }

}

func exampleSessions() -> [Session] {
    [
        Session(id: "demo-running", turnID: "1", title: "论文润色", status: .running,
                summary: "正在核对摘要中的术语，并检查长句的语法与衔接。", updatedAt: Date()),
        Session(id: "demo-done", turnID: "1", title: "菜单栏工具", status: .completed,
                summary: "已完成实现与检查，点击打开对应会话。", updatedAt: Date()),
        Session(id: "demo-wait", turnID: "1", title: "数据整理", status: .waiting,
                summary: "等待你在会话中选择需要处理的数据范围。", updatedAt: Date())
    ]
}
