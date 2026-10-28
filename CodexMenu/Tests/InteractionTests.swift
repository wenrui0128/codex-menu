import XCTest
import AppKit
import QuartzCore
@testable import CodexMenu

final class InteractionTests: XCTestCase {
    private let first = "00000000-0000-4000-8000-000000000001"
    private let second = "00000000-0000-4000-8000-000000000002"

    private func mouseEvent(_ type: NSEvent.EventType, in button: NSButton,
                            flags: NSEvent.ModifierFlags = [], location: NSPoint? = nil) throws -> NSEvent {
        let window = try XCTUnwrap(button.window)
        let point = location ?? button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
    }

    private func click(_ button: NSButton, secondary: Bool = false, control: Bool = false) throws {
        // Give macOS time to finish placing a newly-created independent item.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let down: NSEvent.EventType = secondary ? .rightMouseDown : .leftMouseDown
        let up: NSEvent.EventType = secondary ? .rightMouseUp : .leftMouseUp
        let flags: NSEvent.ModifierFlags = control ? [.control] : []
        // Native status buttons run a tracking loop during mouse-down. Queue
        // the release through NSApplication, as a real mouse click would do.
        NSApp.postEvent(try mouseEvent(up, in: button, flags: flags), atStart: false)
        NSApp.sendEvent(try mouseEvent(down, in: button, flags: flags))
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    }

    func testRightClickControlOpensTheRealMenuAndItsSettingsActionShowsTheWindow() throws {
        _ = NSApplication.shared
        final class MenuProbe: NSObject, NSMenuDelegate {
            var opened = false
            var closed = false
            func menuWillOpen(_ menu: NSMenu) { opened = true }
            func menuDidClose(_ menu: NSMenu) { closed = true }
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let delegate = MenuAppDelegate(reader: LocalSessionStore(root: temporary),
            persistence: StatePersistence(url: temporary.appendingPathComponent("state.json")), demo: true)
        let menu = delegate.buildMenu()
        let probe = MenuProbe()
        menu.delegate = probe
        let settings = try XCTUnwrap(menu.items.first { $0.title == "设置…" })
        let group = StatusItems()
        defer { group.remove() }
        group.onShowAll = {
            let dismiss = Timer(timeInterval: 0.1, repeats: false) { _ in menu.cancelTracking() }
            RunLoop.main.add(dismiss, forMode: .common)
            RunLoop.main.add(dismiss, forMode: .eventTracking)
            StatusMenuPresentation.show(menu, from: group.control.button)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        try click(group.control.button, secondary: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertTrue(probe.opened, "The control must start actual NSMenu tracking")
        XCTAssertTrue(probe.closed)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(settings.action), to: settings.target, from: settings))
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "Codex Menu 设置" && $0.isVisible })
        window.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.appendingPathComponent("state.json").path),
                       "The test must use isolated demo settings")
    }

    func testWindowDeliveredRightClicksOpenTheCorrectPreviewAndReachTheControl() throws {
        _ = NSApplication.shared
        let sessions = [first, second].enumerated().map { index, id in
            Session(id: id, turnID: "turn", title: "会话 \(index)", status: .running,
                    summary: "公开进度 \(index)", updatedAt: Date())
        }
        let group = StatusItems()
        defer { group.remove() }
        group.update(sessions, width: 180, preferences: MenuPreferences(), hiddenCount: 0, readError: nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let presenter = SessionPopoverPresenter()
        defer { presenter.close(animated: false) }
        var previews: [String] = []
        var controls = 0
        group.onOpen = { _ in XCTFail("A right-click must not navigate") }
        group.onContextMenu = { session, _, anchor in
            previews.append(session.id)
            presenter.show(session, from: anchor, readError: nil, onOpen: { _ in }, onShowAll: {})
        }
        group.onShowAll = { controls += 1 }

        for session in sessions {
            let item = try XCTUnwrap(group.items[session.id])
            try click(item.button, secondary: true)
            XCTAssertEqual(presenter.controller?.session.id, session.id)
            XCTAssertTrue(presenter.controller?.view.window?.isVisible == true, "The preview must remain visible after button release")
        }
        XCTAssertEqual(previews, sessions.map(\.id))
        presenter.close(animated: false)
        try click(group.control.button, secondary: true)
        XCTAssertEqual(controls, 1, "The real status window must deliver the control's right-click")
    }

    func testDifferentSessionsSendDifferentURLsToTheChosenApplication() throws {
        let application = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        var requests: [(URL, URL)] = []
        let navigator = ThreadNavigator(resolveApplication: { application }, openURL: { url, app, completion in
            requests.append((url, app)); completion(.success(()))
        })
        navigator.open(threadID: first) { if case .failure(let error) = $0 { XCTFail(error.localizedDescription) } }
        navigator.open(threadID: second) { if case .failure(let error) = $0 { XCTFail(error.localizedDescription) } }
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map { $0.0.path }, ["/\(first)", "/\(second)"])
        XCTAssertTrue(requests.allSatisfy { $0.1 == application })
        for request in requests {
            let parts = try XCTUnwrap(URLComponents(url: request.0, resolvingAgainstBaseURL: false))
            XCTAssertEqual(parts.scheme, "codex")
            XCTAssertEqual(parts.host, "threads")
            XCTAssertEqual(parts.queryItems, [URLQueryItem(name: "hostId", value: "local")])
        }
    }

    func testInvalidSessionDoesNotLaunchAnythingAndOpenFailureIsReported() {
        let navigator = ThreadNavigator(resolveApplication: { URL(fileURLWithPath: "/Applications/ChatGPT.app") }, openURL: { _, _, _ in XCTFail("Invalid thread must not open") })
        navigator.open(threadID: "../other?hostId=remote") { result in
            guard case .failure = result else { return XCTFail("Expected validation failure") }
        }
        let failed = ThreadNavigator(resolveApplication: { URL(fileURLWithPath: "/Applications/ChatGPT.app") }, openURL: { _, _, completion in
            completion(.failure(NavigationFailure.missingApplication))
        })
        var reported = false
        failed.open(threadID: first) { if case .failure = $0 { reported = true } }
        XCTAssertTrue(reported)
    }

    func testNativeButtonsRouteLeftClickToTheirOwnSessionAndRightClickToMenu() throws {
        _ = NSApplication.shared
        var opened: [String] = []
        var contextMenus: [String] = []
        var urls: [URL] = []
        let navigator = ThreadNavigator(resolveApplication: { URL(fileURLWithPath: "/Applications/ChatGPT.app") }, openURL: { url, _, completion in
            urls.append(url)
            completion(.success(()))
        })
        let sessions = [first, second].map {
            Session(id: $0, turnID: "turn", title: "会话", status: .completed, summary: "公开进度", updatedAt: Date())
        }
        let group = StatusItems()
        defer { group.remove() }
        group.onOpen = { session in
            opened.append(session.id)
            navigator.open(threadID: session.id) { if case .failure(let error) = $0 { XCTFail(error.localizedDescription) } }
        }
        group.onContextMenu = { session, _, view in
            XCTAssertTrue(view === group.items[session.id]?.button)
            contextMenus.append(session.id)
        }
        group.update(sessions, width: 240, preferences: MenuPreferences(), hiddenCount: 0, readError: nil)
        let items = group.orderedItems
        let buttons = items.map(\.button)
        XCTAssertFalse(items[0].statusItem === items[1].statusItem)
        XCTAssertFalse(items[0].statusItem === group.control.statusItem)
        XCTAssertFalse(buttons[0] === buttons[1])
        for (item, button) in zip(items, buttons) {
            XCTAssertNotNil(button.target)
            XCTAssertTrue(item.statusItem.button === button)
            XCTAssertNotNil(button.action)
            XCTAssertNil(item.badge.hitTest(NSPoint(x: 120, y: 10)))
            XCTAssertEqual(button.identifier?.rawValue, "CodexMenu.session.\(item.session.id)")
            let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: button.superview)
            XCTAssertTrue(button.hitTest(point) === button, "The system button must receive the click")
        }
        XCTAssertTrue(items.allSatisfy { $0.statusItem.length == 240 })
        for button in buttons { try click(button) }
        XCTAssertEqual(opened, [first, second])
        XCTAssertEqual(urls, try [first, second].map(ThreadNavigator.threadURL))
        for button in buttons { try click(button, secondary: true) }
        try click(buttons[0], control: true)
        XCTAssertEqual(contextMenus, [first, second, first])
        XCTAssertEqual(opened, [first, second], "Right-click must not navigate or dismiss a session")
        XCTAssertEqual(urls.count, 2)

        var updated = sessions[1]
        updated.title = "更新后的第二个会话"
        updated.turnID = "next-turn"
        updated.status = .running
        group.update([sessions[0], updated], width: 300, preferences: MenuPreferences(), hiddenCount: 0, readError: nil)
        XCTAssertTrue(items[1].button === buttons[1], "Progress updates must keep the same native button and target")
        XCTAssertEqual(items[1].statusItem.length, 300)
        XCTAssertEqual(items[1].badge.session, updated)
        group.update([updated], width: 300, preferences: MenuPreferences(), hiddenCount: 0, readError: nil)
        XCTAssertNil(buttons[0].target)
        XCTAssertTrue(group.items[second]?.statusItem === items[1].statusItem)
        try click(buttons[1])
        XCTAssertEqual(opened, [first, second, second], "Removing one icon must preserve the other icon's conversation")
        XCTAssertEqual(urls.last, try ThreadNavigator.threadURL(id: second))
    }

    func testDelayedOpenDoesNotDismissANewerRunningTurn() {
        let old = Session(id: first, turnID: "old", title: "会话", status: .completed, summary: "已完成", updatedAt: Date())
        let active = Session(id: first, turnID: "new", title: "会话", status: .running, summary: "处理中", updatedAt: Date())
        var tracker = SessionTracker(state: SavedState())
        tracker.ingest([old])
        tracker.ingest([active])
        tracker.acknowledge(old)
        XCTAssertEqual(tracker.ordered, [active])
        tracker.ingest([active])
        XCTAssertEqual(tracker.ordered, [active])
    }

    func testIndependentItemsKeepTheirSessionsAcrossReorderingAndHaveOneOverflowControl() throws {
        _ = NSApplication.shared
        let sessions = [first, second].map {
            Session(id: $0, turnID: "turn", title: "会话", status: .running, summary: "公开进度", updatedAt: Date())
        }
        let group = StatusItems()
        defer { group.remove() }
        var opened: [String] = []
        var showAll = 0
        group.onOpen = { opened.append($0.id) }
        group.onShowAll = { showAll += 1 }
        group.update(sessions, width: 240, preferences: MenuPreferences(), hiddenCount: 3, readError: nil)
        let firstButton = try XCTUnwrap(group.items[first]?.button)
        let secondButton = try XCTUnwrap(group.items[second]?.button)
        let control = group.control.button
        var preferences = MenuPreferences()
        preferences.menuFontSize = 15
        preferences.showTitle = false
        group.update(Array(sessions.reversed()), width: 180, preferences: preferences, hiddenCount: 3, readError: nil)
        XCTAssertTrue(group.items[first]?.button === firstButton)
        XCTAssertTrue(group.items[second]?.button === secondButton)
        for button in [secondButton, firstButton] {
            button.performClick(nil)
        }
        XCTAssertEqual(opened, [second, first])
        XCTAssertTrue(control === group.control.button)
        XCTAssertEqual(control.title, "+3")
        control.performClick(nil)
        XCTAssertEqual(showAll, 1)
        group.update([], width: 180, preferences: preferences, hiddenCount: 5, readError: nil)
        XCTAssertEqual(group.control.statusItem.length, StatusItemLayout.controlWidth(hiddenCount: 5))
        XCTAssertTrue(group.items.isEmpty)
        XCTAssertTrue(group.orderedItems.isEmpty)
        XCTAssertEqual(control.title, "+5")
        control.performClick(nil)
        XCTAssertEqual(showAll, 2, "All sessions must stay accessible when none fit as cards")
        XCTAssertEqual(opened, [second, first])
        let expandedWidth = group.control.statusItem.length
        group.update(sessions, width: 180, preferences: preferences, hiddenCount: 0, readError: nil)
        XCTAssertEqual(group.control.statusItem.length, StatusItemLayout.controlWidth)
        XCTAssertLessThan(group.control.statusItem.length, expandedWidth, "Removing the overflow count must also remove its empty space")
        XCTAssertEqual(control.title, "")
    }

    func testIndependentItemLayoutRespectsTheSpaceBudget() {
        for width in [180.0, 240, 480] {
            var preferences = MenuPreferences()
            preferences.cardWidth = width
            preferences.maxVisible = 6
            for budget in [44.0, 180, 240, 528, 900] {
                let layout = StatusItemLayout(sessions: 9, preferences: preferences, budget: budget)
                let occupied = CGFloat(layout.visibleCount) * (layout.cardWidth + StatusItemLayout.spacing) + layout.entryWidth
                XCTAssertLessThanOrEqual(occupied, budget)
                XCTAssertLessThanOrEqual(layout.visibleCount, preferences.maxVisible)
                XCTAssertEqual(layout.cardWidth, width)
            }
        }
    }

    func testStatusLampKeepsPulsingWhenTextIsPausedAndStopsForErrorsOrReducedMotion() {
        _ = NSApplication.shared
        let session = Session(id: first, turnID: "one", title: "会话", status: .running, summary: "公开进度", updatedAt: Date())
        let badge = SessionBadgeView(session: session, width: 240, height: 28)
        badge.scrolling = false
        badge.lamp.update(.running, reduceMotion: false)
        XCTAssertTrue(badge.lamp.isPulsing, "Pausing text must not hide running-state feedback")
        badge.lamp.update(.failed, reduceMotion: false)
        XCTAssertFalse(badge.lamp.isPulsing, "An error must remain steadily lit")
        badge.lamp.update(.completed, reduceMotion: false)
        XCTAssertTrue(badge.lamp.isPulsing)
        badge.lamp.update(.completed, reduceMotion: true)
        XCTAssertFalse(badge.lamp.isPulsing, "Reduced motion must leave a steady completion light")
        badge.lamp.update(.running, motionAllowed: false, reduceMotion: false)
        XCTAssertFalse(badge.lamp.isPulsing, "Unverified old running state must not continue flashing")
        badge.lamp.update(.waiting, reduceMotion: false)
        XCTAssertFalse(badge.lamp.isPulsing, "Waiting must remain distinguishable from running")

        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 40, height: 40),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let lamp = StatusLampView(status: .failed)
        lamp.frame.origin = NSPoint(x: 14, y: 14)
        window.contentView?.addSubview(lamp)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        lamp.update(.running, reduceMotion: false)
        CATransaction.flush()
        var brightness: [Float] = []
        for _ in 0..<9 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            if let opacity = lamp.layer?.sublayers?.last?.presentation()?.opacity { brightness.append(opacity) }
        }
        XCTAssertGreaterThan(brightness.count, 3)
        XCTAssertGreaterThan((brightness.max() ?? 0) - (brightness.min() ?? 0), 0.3,
                             "The visible lamp must actually brighten and dim, not only hold an animation object")
    }

    func testRightClickProgressPanelUpdatesItsSessionWithoutOpeningUntilRequested() throws {
        _ = NSApplication.shared
        let initial = Session(id: first, turnID: "old", title: "第一个会话", status: .running, summary: "第一条进度", updatedAt: Date())
        let other = Session(id: second, turnID: "other", title: "第二个会话", status: .failed, summary: "错误详情", updatedAt: Date())
        let group = StatusItems()
        group.update([initial, other], width: 240, preferences: MenuPreferences(), hiddenCount: 0, readError: nil)
        let firstItem = try XCTUnwrap(group.items[first])
        let secondItem = try XCTUnwrap(group.items[second])
        defer { group.remove() }
        let presenter = SessionPopoverPresenter()
        defer { presenter.close(animated: false) }
        var opened: [Session] = []
        var settingsOpened = 0
        presenter.show(initial, from: firstItem.button, readError: nil,
                       onOpen: { opened.append($0) }, onShowAll: { settingsOpened += 1 })
        let content = try XCTUnwrap(presenter.controller)
        XCTAssertEqual(content.session, initial)
        XCTAssertTrue(opened.isEmpty, "Right-click must not open or dismiss the conversation")
        var updated = initial
        updated.turnID = "new"
        updated.summary = "已经更新的公开进度"
        updated.status = .completed
        presenter.update(sessions: [first: updated, second: other], readError: nil)
        XCTAssertTrue(presenter.controller === content)
        XCTAssertEqual(content.session, updated)
        content.openButton.performClick(nil)
        XCTAssertEqual(opened, [updated], "The panel must open its current turn, not a stale or neighboring conversation")
        XCTAssertNil(presenter.controller)
        presenter.show(other, from: secondItem.button, readError: nil,
                       onOpen: { opened.append($0) }, onShowAll: { settingsOpened += 1 })
        let secondContent = try XCTUnwrap(presenter.controller)
        XCTAssertEqual(secondContent.session, other)
        secondContent.allButton.performClick(nil)
        XCTAssertEqual(settingsOpened, 1)
        XCTAssertEqual(opened, [updated], "Opening settings must not acknowledge any conversation")
        XCTAssertNil(presenter.controller)
    }
}
