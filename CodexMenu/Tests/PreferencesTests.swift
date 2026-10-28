import XCTest
import AppKit
import SwiftUI
@testable import CodexMenu

final class PreferencesTests: XCTestCase {
    func testVersionThreeStateMigratesWithoutLosingRetainedOrAcknowledgedTurns() throws {
        let legacy = Data(#"{"preferences":{"cardWidth":300,"maxVisible":4,"scrolling":false},"sessions":{"one":{"id":"one","turnID":"turn","title":"保留的完成会话","status":"completed","summary":"已完成","updatedAt":100,"archived":false}},"acknowledged":{"other":"old-turn"}}"#.utf8)
        let state = try JSONDecoder().decode(SavedState.self, from: legacy)
        XCTAssertEqual(state.sessions["one"]?.title, "保留的完成会话")
        XCTAssertEqual(state.acknowledged, ["other": "old-turn"])
        XCTAssertEqual(state.preferences.cardWidth, 300)
        XCTAssertEqual(state.preferences.maxVisible, 4)
        XCTAssertFalse(state.preferences.scrolling)
        XCTAssertEqual(state.preferences.menuFontSize, 11)
        XCTAssertEqual(state.preferences.detailFontSize, 13)
        XCTAssertTrue(state.preferences.animateLamps)
        XCTAssertNil(state.sessions["one"]?.startedAt)
        let restored = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored.preferences, state.preferences)
        XCTAssertEqual(restored.sessions, state.sessions)
    }

    func testSettingsModelBindingsPersistOnceAndRejectInvalidGeometry() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let persistence = StatePersistence(url: path)
        let model = PreferencesModel(MenuPreferences())
        var state = SavedState()
        var calls = 0
        model.onChange = { preferences in
            calls += 1
            state.preferences = preferences
            do { try persistence.save(state) }
            catch { XCTFail("Settings did not persist: \(error)") }
        }
        model.binding(\.menuFontSize).wrappedValue = 14.5
        model.binding(\.detailFontSize).wrappedValue = 20
        model.binding(\.theme).wrappedValue = .dark
        model.binding(\.scrollSpeed).wrappedValue = 48
        XCTAssertEqual(calls, 4)
        XCTAssertEqual(try persistence.load().preferences, model.preferences)
        var invalid = model.preferences
        invalid.menuFontSize = .infinity
        invalid.detailFontSize = 1000
        invalid.cardWidth = -100
        invalid.maxVisible = 0
        invalid.scrollSpeed = .nan
        model.replace(invalid)
        XCTAssertEqual(model.preferences.menuFontSize, 11)
        XCTAssertEqual(model.preferences.detailFontSize, 20)
        XCTAssertEqual(model.preferences.cardWidth, 180)
        XCTAssertEqual(model.preferences.maxVisible, 1)
        XCTAssertEqual(model.preferences.scrollSpeed, 24)
        XCTAssertNoThrow(try persistence.load())
    }

    func testElapsedUsesTheCurrentTurnStartAndNeverInventsMissingStartTimes() {
        let now = Date(timeIntervalSince1970: 2000000000)
        var session = Session(id: "one", turnID: "turn", title: "会话", status: .running, summary: "公开进度", updatedAt: now)
        XCTAssertNil(SessionMenuPresentation.elapsed(session, now: now))
        session.startedAt = now.addingTimeInterval(-65)
        XCTAssertEqual(SessionMenuPresentation.elapsed(session, now: now), "1:05")
        session.startedAt = now.addingTimeInterval(-3665)
        XCTAssertEqual(SessionMenuPresentation.elapsed(session, now: now), "1:01:05")
        var preferences = MenuPreferences()
        XCTAssertTrue(SessionMenuPresentation.title(for: session, preferences: preferences, now: now).string.contains("1:01:05"))
        preferences.showElapsed = false
        XCTAssertFalse(SessionMenuPresentation.title(for: session, preferences: preferences, now: now).string.contains("1:01:05"))
        session.status = .completed
        XCTAssertNil(SessionMenuPresentation.elapsed(session, now: now))
        session.status = .running
        session.startedAt = now.addingTimeInterval(10)
        XCTAssertNil(SessionMenuPresentation.elapsed(session, now: now))
    }

    func testLargestFontsResizeDetailAndPreserveTheNativeClickTarget() throws {
        _ = NSApplication.shared
        let session = Session(id: "one", turnID: "turn", title: "一段较长的会话标题，用于检查最大字号", status: .running,
                              summary: String(repeating: "可以选取和滚动的公开进度。", count: 30), updatedAt: Date())
        var preferences = MenuPreferences()
        preferences.menuFontSize = 15
        preferences.detailFontSize = 20
        preferences.animateLamps = false
        let item = SessionMenuItem(session: session, width: 180)
        defer { item.remove() }
        let button = item.button
        var opened: [String] = []
        item.onOpen = { opened.append($0.id) }
        item.update(session, width: 180, scrolling: false, preferences: preferences)
        let titledWidth = item.badge.progressFrame.width
        preferences.showTitle = false
        item.update(session, width: 180, scrolling: false, preferences: preferences)
        XCTAssertGreaterThan(item.badge.progressFrame.width, titledWidth)
        XCTAssertFalse(item.badge.lamp.isPulsing)
        XCTAssertTrue(item.button === button)
        button.performClick(nil)
        XCTAssertEqual(opened, ["one"])

        let detail = SessionDetailViewController(session: session)
        _ = detail.view
        let normal = detail.preferredContentSize
        detail.apply(preferences)
        detail.update(session)
        detail.view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(detail.preferredContentSize.height, normal.height)
        XCTAssertEqual(detail.preferredContentSize.width, 440)
        XCTAssertFalse(detail.lamp.isPulsing)
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let text = try XCTUnwrap(descendants(detail.view).compactMap { $0 as? NSTextView }.first)
        XCTAssertEqual(text.font?.pointSize, 20)
        XCTAssertEqual(text.string, session.summary)
        XCTAssertGreaterThan(text.enclosingScrollView?.bounds.height ?? 0, 150)
        XCTAssertLessThanOrEqual(text.frame.width, (text.enclosingScrollView?.contentSize.width ?? 0) + 0.5,
                                 "Long progress must wrap inside the visible scroll region at the largest font")
        XCTAssertFalse(detail.openButton.hasAmbiguousLayout)
        XCTAssertFalse(detail.view.hasAmbiguousLayout)
    }

    func testExplicitLightThemeOverridesADarkMenuBarAndSystemUsesTransparentFill() throws {
        _ = NSApplication.shared
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
        host.appearance = NSAppearance(named: .darkAqua)
        let badge = SessionBadgeView(session: exampleSessions()[0], width: 240, height: 28)
        host.addSubview(badge)
        var preferences = MenuPreferences()
        preferences.theme = .light
        badge.apply(preferences)
        XCTAssertEqual(badge.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), .aqua,
                       "Status items must apply the selected appearance themselves")
        let light = MenuPalette.badgeColors(preferences: preferences, appearance: host.effectiveAppearance)
        let lightFill = try XCTUnwrap(light.background.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(lightFill.redComponent, 0.9)
        XCTAssertLessThan(try XCTUnwrap(light.foreground.usingColorSpace(.sRGB)).redComponent, 0.3)
        preferences.theme = .system
        badge.apply(preferences)
        XCTAssertNil(badge.appearance)
        XCTAssertEqual(MenuPalette.badgeColors(preferences: preferences, appearance: host.effectiveAppearance).background.alphaComponent, 0)
    }

    func testCustomColorsAndOpacityPersistAndApplyIndependentlyOfWindowTheme() throws {
        let model = PreferencesModel(MenuPreferences())
        model.binding(\.customColors).wrappedValue = true
        model.colorBinding(\.backgroundHex).wrappedValue = Color(nsColor: MenuPalette.color(0xE8F1FF))
        model.colorBinding(\.textHex).wrappedValue = Color(nsColor: MenuPalette.color(0x173D63))
        model.binding(\.backgroundOpacity).wrappedValue = 0.4
        let saved = try JSONDecoder().decode(MenuPreferences.self, from: JSONEncoder().encode(model.preferences))
        XCTAssertEqual(saved, model.preferences)
        XCTAssertEqual(saved.backgroundHex, 0xE8F1FF)
        XCTAssertEqual(saved.textHex, 0x173D63)
        let colors = MenuPalette.badgeColors(preferences: saved, appearance: NSAppearance(named: .darkAqua)!)
        XCTAssertEqual(colors.background.alphaComponent, 0.4, accuracy: 0.001)
        XCTAssertEqual(colors.foreground, MenuPalette.color(0x173D63))
        var invalid = saved
        invalid.backgroundOpacity = .infinity
        XCTAssertEqual(invalid.normalized.backgroundOpacity, 0.85)
        invalid.backgroundOpacity = -1
        XCTAssertEqual(invalid.normalized.backgroundOpacity, 0)
    }

    func testWholeSessionOutlineBreathesWithoutScrollingAndStopsForErrors() {
        _ = NSApplication.shared
        let badge = SessionBadgeView(session: exampleSessions()[0], width: 240, height: 28)
        badge.scrolling = false
        let outline = badge.statusOutline
        outline.update(.running, reduceMotion: false)
        XCTAssertTrue(outline.isPulsing)
        outline.update(.completed, reduceMotion: false)
        XCTAssertTrue(outline.isPulsing)
        outline.update(.failed, reduceMotion: false)
        XCTAssertFalse(outline.isPulsing)
        outline.update(.running, reduceMotion: true)
        XCTAssertFalse(outline.isPulsing)
        badge.setStatusVerified(false)
        XCTAssertEqual(outline.status, .unknown)
        XCTAssertFalse(outline.isPulsing)
        XCTAssertNil(outline.hitTest(.zero), "The outline must not intercept clicks or right-clicks")
    }
}
