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
        XCTAssertEqual(state.preferences.backgroundHex, MenuPreferences.defaultBackgroundHex)
        XCTAssertEqual(state.preferences.backgroundOpacity, 1)
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
        model.binding(\.showTitle).wrappedValue = false
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

    func testLegacyLightAndCutoutSettingsMigrateToOpaqueGraphite() throws {
        let legacy = Data(#"{"theme":"light","cutoutText":true,"customColors":false,"backgroundHex":16777215,"textHex":2435634,"backgroundOpacity":0.85,"menuFontSize":14,"scrollSpeed":32}"#.utf8)
        let preferences = try JSONDecoder().decode(MenuPreferences.self, from: legacy)
        XCTAssertEqual(preferences.backgroundHex, MenuPreferences.defaultBackgroundHex)
        XCTAssertEqual(preferences.textHex, MenuPreferences.defaultTextHex)
        XCTAssertEqual(preferences.backgroundOpacity, 1)
        XCTAssertEqual(preferences.menuFontSize, 14)
        XCTAssertEqual(preferences.scrollSpeed, 32)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any])
        XCTAssertNil(encoded["theme"])
        XCTAssertNil(encoded["cutoutText"])
    }

    func testGraphiteColorsStayFixedUnderSystemAppearances() throws {
        _ = NSApplication.shared
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
        let badge = SessionBadgeView(session: exampleSessions()[0], width: 240, height: 28)
        host.addSubview(badge)
        badge.apply(MenuPreferences())
        for name in [NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua] {
            host.appearance = NSAppearance(named: name)
            XCTAssertEqual(badge.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), .darkAqua)
            XCTAssertFalse(badge.allowsVibrancy)
            let colors = MenuPalette.badgeColors(preferences: badge.preferences)
            XCTAssertEqual(colors.background, MenuPalette.color(0x3C434E))
            XCTAssertEqual(colors.background.alphaComponent, 1)
            func luminance(_ color: NSColor) throws -> Double {
                let rgb = try XCTUnwrap(color.usingColorSpace(.sRGB))
                func linear(_ v: CGFloat) -> Double { v <= 0.04045 ? Double(v / 12.92) : pow(Double((v + 0.055) / 1.055), 2.4) }
                return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
            }
            let background = try luminance(colors.background)
            for ink in [colors.foreground, colors.secondary] {
                XCTAssertGreaterThanOrEqual((try luminance(ink) + 0.05) / (background + 0.05), 4.5)
            }
        }
    }

    func testCustomColorsAndOpacityPersistIndependentlyOfSystemAppearance() throws {
        let model = PreferencesModel(MenuPreferences())
        model.binding(\.customColors).wrappedValue = true
        model.colorBinding(\.backgroundHex).wrappedValue = Color(nsColor: MenuPalette.color(0xE8F1FF))
        model.colorBinding(\.textHex).wrappedValue = Color(nsColor: MenuPalette.color(0x173D63))
        model.binding(\.backgroundOpacity).wrappedValue = 0.4
        let saved = try JSONDecoder().decode(MenuPreferences.self, from: JSONEncoder().encode(model.preferences))
        XCTAssertEqual(saved, model.preferences)
        XCTAssertEqual(saved.backgroundHex, 0xE8F1FF)
        XCTAssertEqual(saved.textHex, 0x173D63)
        let colors = MenuPalette.badgeColors(preferences: saved)
        XCTAssertEqual(colors.background.alphaComponent, 0.4, accuracy: 0.001)
        XCTAssertEqual(colors.foreground, MenuPalette.color(0x173D63))
        var invalid = saved
        invalid.backgroundOpacity = .infinity
        XCTAssertEqual(invalid.normalized.backgroundOpacity, 1)
        invalid.backgroundOpacity = -1
        XCTAssertEqual(invalid.normalized.backgroundOpacity, 0)
    }

    func testDefaultGraphiteCapsuleDrawsOpaqueLightGlyphs() throws {
        _ = NSApplication.shared
        let session = Session(id: "solid-ink", turnID: "turn", title: "MMMM", status: .running,
                              summary: "MMMMMMMM", updatedAt: Date())
        let badge = SessionBadgeView(session: session, width: 240, height: 28)
        var preferences = MenuPreferences()
        preferences.menuFontSize = 15
        preferences.scrolling = false
        badge.apply(preferences)
        let colors = MenuPalette.badgeColors(preferences: preferences)
        XCTAssertEqual(colors.background, MenuPalette.color(0x3C434E))
        XCTAssertEqual(colors.background.alphaComponent, 1)

        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 480, pixelsHigh: 56,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        graphics.cgContext.clear(CGRect(x: 0, y: 0, width: 480, height: 56))
        graphics.cgContext.scaleBy(x: 2, y: 2)
        badge.draw(badge.bounds)
        NSGraphicsContext.restoreGraphicsState()

        // Glyphs must remain solid, light ink rather than reveal the menu bar.
        var holes = 0
        var ink = 0
        for y in 16..<40 {
            for x in 58..<170 {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let alpha = color.alphaComponent
                if alpha < 0.05 { holes += 1 }
                if alpha > 0.99 && color.redComponent > 0.85 { ink += 1 }
            }
        }
        XCTAssertEqual(holes, 0, "Text must stay opaque when the menu bar material changes")
        XCTAssertGreaterThan(ink, 50, "Light glyphs must remain visible over the dark fill")
    }

    func testBadgePixelsStayFixedWhenMenuMaterialBecomesInactive() throws {
        _ = NSApplication.shared
        let material = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
        material.material = .menu
        material.blendingMode = .behindWindow
        material.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: material.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = material
        let badge = SessionBadgeView(session: exampleSessions()[0], width: 240, height: 28)
        var preferences = MenuPreferences()
        preferences.scrolling = false
        preferences.animateLamps = false
        badge.apply(preferences)
        material.addSubview(badge)
        func pixels(_ state: NSVisualEffectView.State) throws -> [NSColor] {
            material.state = state
            material.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(badge.bitmapImageRepForCachingDisplay(in: badge.bounds))
            badge.cacheDisplay(in: badge.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / badge.bounds.width
            return try (8..<20).flatMap { y in
                try (24..<130).map { x in
                    try XCTUnwrap(bitmap.colorAt(x: Int(CGFloat(x) * scale), y: Int(CGFloat(y) * scale)))
                }
            }
        }
        let active = try pixels(.active)
        let inactive = try pixels(.inactive)
        XCTAssertEqual(active, inactive, "Losing active menu material must not fade the badge or its text")
        XCTAssertTrue(inactive.allSatisfy { $0.alphaComponent > 0.99 })
        withExtendedLifetime(window) {}
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

    func testShortTitlesLeaveOnlyTheDividerGapBeforeScrollingProgress() {
        _ = NSApplication.shared
        var sample = exampleSessions()[0]
        sample.title = "测试"
        let badge = SessionBadgeView(session: sample, width: 480, height: 28)
        var preferences = MenuPreferences()
        preferences.menuFontSize = 15
        badge.apply(preferences)
        let measured = ceil(NSAttributedString(string: sample.title,
            attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium)]).size().width)
        XCTAssertEqual(badge.titleFrame.width, measured)
        XCTAssertEqual(badge.progressFrame.minX - badge.titleFrame.maxX, 12)
        let shortStart = badge.progressFrame.minX
        sample.title = String(repeating: "较长标题", count: 8)
        badge.update(sample)
        XCTAssertGreaterThan(badge.progressFrame.minX, shortStart)
        XCTAssertGreaterThan(badge.progressFrame.width, 200)
        preferences.showTitle = false
        badge.apply(preferences)
        XCTAssertEqual(badge.progressFrame.minX, 23)
    }
}
