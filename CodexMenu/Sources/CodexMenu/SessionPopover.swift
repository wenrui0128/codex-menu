import AppKit

final class SessionDetailViewController: NSViewController {
    private(set) var session: Session
    var onOpen: ((Session) -> Void)?
    var onShowAll: (() -> Void)?
    let lamp: StatusLampView
    let openButton = NSButton(title: "打开此会话", target: nil, action: nil)
    let allButton = NSButton(title: "全部会话与设置", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let updatedLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let progressLabel = NSTextField(labelWithString: "最新公开进度")
    private let progressText = NSTextView()
    private let progressScroll = NSScrollView()
    private let footnote = NSTextField(wrappingLabelWithString: "")
    private var readError: String?
    private var preferences = MenuPreferences()
    private var rowHeights: [NSLayoutConstraint] = []
    private let copyButton = NSButton(title: "复制", target: nil, action: nil)

    init(session: Session) {
        self.session = session
        lamp = StatusLampView(status: session.status)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let surface = MenuPanelSurface(frame: NSRect(x: 0, y: 0, width: 400, height: 342))
        view = surface
        preferredContentSize = surface.frame.size

        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.lineBreakMode = .byTruncatingTail
        updatedLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let statusRow = NSStackView(views: [lamp, statusLabel, spacer, updatedLabel])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 6
        lamp.widthAnchor.constraint(equalToConstant: 12).isActive = true
        lamp.heightAnchor.constraint(equalToConstant: 12).isActive = true

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isSelectable = true
        progressLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.imagePosition = .imageLeading
        copyButton.target = self
        copyButton.action = #selector(copyProgress)
        copyButton.setAccessibilityLabel("复制最新公开进度")
        let progressSpacer = NSView()
        progressSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let progressHeader = NSStackView(views: [progressLabel, progressSpacer, copyButton])
        progressHeader.orientation = .horizontal
        progressHeader.alignment = .centerY

        let scroll = progressScroll
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        progressText.frame = NSRect(x: 0, y: 0, width: 332, height: 110)
        progressText.minSize = NSSize(width: 0, height: 110)
        progressText.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        progressText.isVerticallyResizable = true
        progressText.isHorizontallyResizable = false
        progressText.autoresizingMask = [.width]
        progressText.drawsBackground = false
        progressText.isEditable = false
        progressText.isSelectable = true
        progressText.isRichText = false
        progressText.textContainerInset = .zero
        progressText.textContainer?.lineFragmentPadding = 0
        progressText.textContainer?.widthTracksTextView = true
        progressText.textContainer?.containerSize = NSSize(width: 332, height: CGFloat.greatestFiniteMagnitude)
        progressText.setAccessibilityLabel("最新公开进度")
        scroll.documentView = progressText

        let separator = NSBox()
        separator.boxType = .separator
        footnote.font = .systemFont(ofSize: 10.5)
        footnote.maximumNumberOfLines = 2
        footnote.lineBreakMode = .byTruncatingTail

        openButton.target = self
        openButton.action = #selector(openSession)
        openButton.bezelStyle = .rounded
        openButton.controlSize = .regular
        openButton.keyEquivalent = "\r"
        openButton.image = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: nil)
        openButton.imagePosition = .imageTrailing
        openButton.font = .systemFont(ofSize: 12, weight: .medium)
        allButton.target = self
        allButton.action = #selector(showAll)
        allButton.bezelStyle = .inline
        allButton.isBordered = false
        allButton.font = .systemFont(ofSize: 11)
        allButton.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        allButton.imagePosition = .imageLeading
        let buttonSpacer = NSView()
        buttonSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [allButton, buttonSpacer, openButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 10

        let rows: [(NSView, CGFloat)] = [(statusRow, 16), (titleLabel, 38), (progressHeader, 18),
                                       (scroll, 120), (separator, 1), (footnote, 30), (buttons, 28)]
        let stack = NSStackView(views: rows.map(\.0))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: surface.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -18)
        ])
        for (row, height) in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            let constraint = row.heightAnchor.constraint(equalToConstant: height)
            constraint.isActive = true
            rowHeights.append(constraint)
        }
        apply(preferences)
        update(session, readError: readError)
    }

    func apply(_ preferences: MenuPreferences) {
        self.preferences = preferences.normalized
        guard isViewLoaded else { return }
        view.appearance = MenuPalette.appearance
        let body = CGFloat(self.preferences.detailFontSize)
        let meta = min(14, max(11, body - 2))
        statusLabel.font = .systemFont(ofSize: meta, weight: .medium)
        updatedLabel.font = .monospacedDigitSystemFont(ofSize: meta - 0.5, weight: .regular)
        titleLabel.font = .systemFont(ofSize: max(15, body + 2), weight: .semibold)
        progressLabel.font = .systemFont(ofSize: meta, weight: .medium)
        footnote.font = .systemFont(ofSize: meta)
        copyButton.font = .systemFont(ofSize: meta)
        openButton.font = .systemFont(ofSize: min(16, body), weight: .medium)
        allButton.font = .systemFont(ofSize: meta)
        let heights: [CGFloat] = [meta + 5, max(38, (body + 2) * 2.5), meta + 7,
                                  max(120, body * 8), 1, max(30, meta * 2.8), max(28, body + 12)]
        for (constraint, height) in zip(rowHeights, heights) { constraint.constant = ceil(height) }
        preferredContentSize = NSSize(width: body > 16 ? 440 : 400, height: heights.map { ceil($0) }.reduce(96, +))
        view.setFrameSize(preferredContentSize)
        view.layoutSubtreeIfNeeded()
        layoutProgress()
        applyProgressFont()
        lamp.update(session.status, motionAllowed: self.preferences.animateLamps && readError == nil)
    }

    private func applyProgressFont() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        progressText.textStorage?.addAttributes([
            .font: NSFont.systemFont(ofSize: preferences.detailFontSize), .paragraphStyle: paragraph
        ], range: NSRange(location: 0, length: progressText.textStorage?.length ?? 0))
    }

    func update(_ value: Session, readError: String? = nil) {
        precondition(value.id == session.id, "A progress panel cannot change conversations")
        session = value
        self.readError = readError
        guard isViewLoaded else { return }
        titleLabel.stringValue = value.title
        titleLabel.toolTip = value.title
        statusLabel.stringValue = readError == nil ? value.status.label : "读取失败 · 上次记录"
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        updatedLabel.stringValue = "更新于 \(formatter.string(from: value.updatedAt))"
        lamp.update(readError == nil ? value.status : .unknown, motionAllowed: preferences.animateLamps && readError == nil)
        if progressText.string != value.summary {
            progressText.string = value.summary
            applyProgressFont()
            progressText.scrollToBeginningOfDocument(nil)
            copyButton.title = "复制"
        }
        footnote.stringValue = readError.map { "读取失败，以上为保留的进度。\n\(compactText($0, limit: 80))" }
            ?? (value.status.isTerminal ? "此条目会一直保留。打开会话后，仅收起这一条。" : "打开会话后，菜单栏继续显示进度。")
        openButton.setAccessibilityHelp(value.status.isTerminal ? "打开当前会话并收起此条目" : "打开当前会话，保留进度图标")
        refreshColors()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(openButton)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutProgress()
    }

    private func layoutProgress() {
        // The document is installed before Auto Layout sizes its scroll view.
        // Match the clip width explicitly so font changes wrap instead of
        // extending a line beyond the right edge of the visible progress area.
        let width = progressScroll.contentSize.width
        guard width > 0 else { return }
        if abs(progressText.frame.width - width) > 0.5 {
            progressText.setFrameSize(NSSize(width: width, height: progressText.frame.height))
        }
        progressText.textContainer?.containerSize.width = width
    }

    func refreshColors() {
        let dark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        titleLabel.textColor = MenuPalette.foreground(dark: dark)
        statusLabel.textColor = MenuPalette.foreground(dark: dark)
        for label in [updatedLabel, progressLabel, footnote] { label.textColor = MenuPalette.secondary(dark: dark) }
        progressText.textColor = MenuPalette.foreground(dark: dark)
        allButton.contentTintColor = MenuPalette.secondary(dark: dark)
        copyButton.contentTintColor = MenuPalette.secondary(dark: dark)
        view.needsDisplay = true
    }

    @objc private func openSession() { onOpen?(session) }
    @objc private func showAll() { onShowAll?() }
    @objc private func copyProgress() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.summary, forType: .string)
        copyButton.title = "已复制"
    }
}

final class SessionPopoverPresenter: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?
    private(set) var controller: SessionDetailViewController?

    func show(_ session: Session, from anchor: NSView, readError: String?, preferences: MenuPreferences = MenuPreferences(),
              onOpen: @escaping (Session) -> Void, onShowAll: @escaping () -> Void) {
        if controller?.session.id == session.id, popover?.isShown == true { close(); return }
        close(animated: false)
        let content = SessionDetailViewController(session: session)
        _ = content.view
        content.apply(preferences)
        content.update(session, readError: readError)
        content.onOpen = { [weak self] value in self?.close(animated: false); onOpen(value) }
        content.onShowAll = { [weak self] in self?.close(animated: false); onShowAll() }
        let panel = NSPopover()
        panel.behavior = .transient
        panel.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.contentViewController = content
        panel.contentSize = content.preferredContentSize
        panel.delegate = self
        controller = content
        popover = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    func update(sessions: [String: Session], readError: String?, preferences: MenuPreferences = MenuPreferences()) {
        guard let content = controller else { return }
        guard let session = sessions[content.session.id] else { close(); return }
        content.update(session, readError: readError)
        content.apply(preferences)
        popover?.contentSize = content.preferredContentSize
        popover?.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func close(animated: Bool = true) {
        let previous = popover
        popover = nil
        controller = nil
        if !animated { previous?.animates = false }
        previous?.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPopover, panel === popover else { return }
        popover = nil
        controller = nil
    }
}
