import AppKit
import SwiftUI

/// Uses production views and isolated sample data; does not capture the screen.
func renderMenuPreview(to path: String, dark: Bool, largeFont: Bool = false,
                       theme: MenuTheme = .system, customColors: Bool = false) throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 1080, height: 630))
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
    canvas.appearance = appearance
    canvas.wantsLayer = true
    canvas.layer?.backgroundColor = MenuPalette.color(dark ? 0x292D33 : 0xEBEEF2).cgColor
    func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular,
               secondary: Bool = false) {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.frame = NSRect(x: x, y: y, width: 1080 - x - 32, height: size + 12)
        field.textColor = secondary ? MenuPalette.secondary(dark: dark) : MenuPalette.foreground(dark: dark)
        canvas.addSubview(field)
    }
    label("Codex Menu", x: 32, y: 560, size: 26, weight: .semibold)
    label("独立会话图标 · 透明底色 · 环绕状态光", x: 32, y: 532, size: 14, secondary: true)
    var preferences = MenuPreferences()
    preferences.theme = theme
    preferences.customColors = customColors
    if largeFont { preferences.menuFontSize = 15; preferences.detailFontSize = 20 }
    let bar = NSView(frame: NSRect(x: 32, y: 458, width: 1016, height: 42))
    bar.wantsLayer = true
    bar.layer?.cornerRadius = 10
    bar.layer?.backgroundColor = MenuPalette.color(dark ? 0x34383F : 0xE1E5EB).cgColor
    canvas.addSubview(bar)
    let entryWidth = StatusItemLayout.controlWidth
    let entry = NSImageView(frame: NSRect(x: 8 + (entryWidth - 20) / 2, y: 11, width: 20, height: 20))
    entry.image = AppArtwork.controlIcon(hasReadError: false)
    bar.addSubview(entry)
    var samples = exampleSessions()
    samples[2].status = .failed
    samples[2].summary = "读取文件时发生错误，进入会话查看详情。"
    var previewPreferences = preferences
    previewPreferences.scrolling = false
    previewPreferences.animateLamps = false
    for (index, session) in samples.enumerated() {
        let badge = SessionBadgeView(session: session, width: 310, height: 28)
        badge.apply(previewPreferences)
        badge.frame.origin = NSPoint(x: 8 + entryWidth + StatusItemLayout.spacing + CGFloat(index) * 318, y: 7)
        bar.addSubview(badge)
    }
    if !largeFont {
        label("黄色呼吸：运行中    红色常亮：出错    绿色呼吸：已完成", x: 32, y: 422, size: 12, secondary: true)
    }

    let detail = SessionDetailViewController(session: samples[0])
    let panel = detail.view
    detail.apply(preferences)
    panel.frame.origin = NSPoint(x: 32, y: largeFont ? 18 : 42)
    panel.wantsLayer = true
    panel.layer?.cornerRadius = 12
    panel.layer?.masksToBounds = true
    canvas.addSubview(panel)
    detail.update(samples[0])
    detail.lamp.update(samples[0].status, motionAllowed: false)
    label("按你的习惯显示。", x: 500, y: 326, size: 23, weight: .semibold)
    label("字号、宽度与滚动速度都可以即时调整。", x: 500, y: 286, size: 13, secondary: true)
    label("每个图标独立绑定会话，可单独调整位置。", x: 500, y: 256, size: 13, secondary: true)
    label("右键查看、选取和复制最新公开进度。", x: 500, y: 226, size: 13, secondary: true)
    label("完成后保留，进入会话后只收起这一条。", x: 500, y: 196, size: 13, secondary: true)
    if !largeFont {
        label("左键打开会话 · 右键查看完整进度 · 悬停暂停文字滚动",
              x: 32, y: 14, size: 11, secondary: true)
    }
    let window = NSWindow(contentRect: canvas.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = canvas
    canvas.layoutSubtreeIfNeeded()
    detail.refreshColors()
    guard let representation = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { return }
    canvas.cacheDisplay(in: canvas.bounds, to: representation)
    if let data = representation.representation(using: .png, properties: [:]) {
        try data.write(to: URL(fileURLWithPath: path))
        print(path)
    }
    withExtendedLifetime(detail) {}
}

func renderSettingsPreview(to path: String, dark: Bool, largeFont: Bool = false, customColors: Bool = false) throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    var preferences = MenuPreferences()
    preferences.theme = dark ? .dark : .light
    preferences.customColors = customColors
    if largeFont { preferences.menuFontSize = 15; preferences.detailFontSize = 20 }
    let model = PreferencesModel(preferences)
    let login = LoginItemModel(preview: true)
    let host = NSHostingController(rootView: MenuSettingsView(model: model, login: login, onDone: {}, initialTab: customColors ? 1 : 0))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = host
    host.view.frame = NSRect(x: 0, y: 0, width: 560, height: 720)
    host.view.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    guard let representation = host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds) else {
        throw StoreFailure(message: "无法渲染设置预览")
    }
    host.view.cacheDisplay(in: host.view.bounds, to: representation)
    if let data = representation.representation(using: .png, properties: [:]) {
        try data.write(to: URL(fileURLWithPath: path))
        print(path)
    }
    withExtendedLifetime((model, login, host, window)) {}
}
