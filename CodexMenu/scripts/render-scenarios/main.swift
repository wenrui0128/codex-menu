import AppKit
import SwiftUI

// Offscreen artwork only. No status items, session-store reads, login-item
// registration, URLs, or settings persistence are created by this renderer.
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "review-scenarios")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
NSTimeZone.default = TimeZone(identifier: "Asia/Shanghai")!
let fixedTime = ISO8601DateFormatter().date(from: "2026-10-28T02:24:12Z")!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    MenuPalette.color(hex).withAlphaComponent(alpha)
}

func box(_ rect: NSRect, _ fill: NSColor, radius: CGFloat = 0, border: NSColor? = nil) {
    fill.setFill()
    let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    shape.fill()
    if let border { border.setStroke(); shape.lineWidth = 0.7; shape.stroke() }
}

func label(_ string: String, x: CGFloat, y: CGFloat, width: CGFloat = 1000,
           size: CGFloat = 13, weight: NSFont.Weight = .regular,
           ink: NSColor = .labelColor, mono: Bool = false) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byTruncatingTail
    style.lineSpacing = 5
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                    : NSFont.systemFont(ofSize: size, weight: weight)
    (string as NSString).draw(in: NSRect(x: x, y: y, width: width, height: 80),
        withAttributes: [.font: font, .foregroundColor: ink, .paragraphStyle: style])
}

func symbol(_ name: String, x: CGFloat, y: CGFloat, width: CGFloat = 16, ink: NSColor) {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
    let tinted = NSImage(size: image.size, flipped: false) { bounds in
        image.draw(in: bounds)
        ink.setFill()
        bounds.fill(using: .sourceAtop)
        return true
    }
    tinted.draw(in: NSRect(x: x, y: y, width: width, height: 16),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}

final class ScenarioCanvas: NSView {
    let dark: Bool
    let number: Int
    var selectedPanel = false
    var settings = false
    override var isFlipped: Bool { true }

    init(dark: Bool, number: Int) {
        self.dark = dark
        self.number = number
        super.init(frame: NSRect(x: 0, y: 0, width: 1600, height: 1000))
        appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSGradient(starting: color(dark ? 0x233A42 : 0xCAD8E0),
                   ending: color(dark ? 0x161F32 : 0xAEBFD5))!.draw(in: bounds, angle: 18)
        box(NSRect(x: -130, y: 480, width: 1250, height: 760),
            color(dark ? 0x3C6261 : 0xE2E9DE, alpha: 0.22), radius: 360)
        drawWorkspace()
        if settings { box(NSRect(x: 0, y: 29, width: 1600, height: 858), color(0x182330, alpha: 0.16)) }
        drawMenu()
        drawCaption()
    }

    private func drawMenu() {
        let fg = color(dark ? 0xF2F4F7 : 0x1D2632)
        box(NSRect(x: 0, y: 0, width: 1600, height: 30), color(dark ? 0x303D48 : 0xE6EDF1, alpha: 0.97))
        symbol("apple.logo", x: 18, y: 6, width: 16, ink: fg)
        label("工作区", x: 52, y: 6, width: 65, size: 13, weight: .semibold, ink: fg)
        for (index, title) in ["文件", "编辑", "视图", "终端", "帮助"].enumerated() {
            label(title, x: 120 + CGFloat(index) * 47, y: 6, width: 44, size: 13, ink: fg)
        }
        if let icon = NSImage(contentsOfFile: "Resources/AppIcon.png") {
            icon.draw(in: NSRect(x: 514, y: 5, width: 20, height: 20))
        }
        symbol("wifi", x: 1372, y: 7, width: 18, ink: fg)
        symbol("battery.100percent", x: 1405, y: 7, width: 24, ink: fg)
        label("周三 10月28日 10:24", x: 1444, y: 7, width: 150, size: 12, ink: fg)
    }

    private func drawWorkspace() {
        let fg = color(dark ? 0xDDE4EE : 0x313C4B)
        let secondary = color(dark ? 0x8F9FAF : 0x697787)
        let window = NSRect(x: 44, y: 78, width: 1512, height: 788)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color(0x132238, alpha: 0.22)
        shadow.shadowBlurRadius = 26
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        box(window, color(dark ? 0x202731 : 0xFFFFFF), radius: 12)
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: window, xRadius: 12, yRadius: 12).addClip()
        box(NSRect(x: 44, y: 78, width: 1512, height: 45), color(dark ? 0x303844 : 0xF3F5F7))
        for (index, hex) in [UInt32(0xF16A66), 0xEEC04F, 0x60C58B].enumerated() {
            box(NSRect(x: 64 + CGFloat(index) * 20, y: 94, width: 12, height: 12), color(hex), radius: 6)
        }
        label("storefront  /  开发工作区", x: 670, y: 92, width: 350, size: 13, weight: .medium, ink: fg)
        box(NSRect(x: 44, y: 123, width: 208, height: 718), color(dark ? 0x252D38 : 0xF7F9FB))
        label("资源管理器", x: 67, y: 146, size: 11, weight: .semibold, ink: secondary)
        let files = ["▾  STOREFRONT", "  ▾  src", "    ▾  components", "        CartSummary.tsx", "        CheckoutForm.tsx", "    ▾  pages", "        Checkout.tsx", "    ▾  styles", "        checkout.css", "  ▾  tests", "      checkout.spec.ts", "  ▾  docs", "      checkout.md", "  package.json", "  tsconfig.json"]
        box(NSRect(x: 44, y: 356, width: 208, height: 29), color(dark ? 0x354355 : 0xE6EDF7))
        for (index, file) in files.enumerated() {
            label(file, x: 64, y: 182 + CGFloat(index) * 29, width: 183, size: 12, ink: fg)
        }
        box(NSRect(x: 252, y: 123, width: 815, height: 38), color(dark ? 0x29313D : 0xF5F7FA))
        box(NSRect(x: 252, y: 123, width: 177, height: 38), color(dark ? 0x202731 : 0xFFFFFF))
        label("Checkout.tsx    ×", x: 275, y: 134, size: 12, ink: fg)
        label("checkout.spec.ts", x: 453, y: 134, size: 12, ink: secondary)
        label("src  ›  pages  ›  Checkout.tsx", x: 280, y: 177, size: 11, ink: secondary)
        let code: [(String, UInt32)] = [
            ("import { useState } from 'react';", 0xBD9BDD),
            ("import { CartSummary } from '../components/CartSummary';", 0xBD9BDD),
            ("import { CheckoutForm } from '../components/CheckoutForm';", 0xBD9BDD),
            ("", 0xB5C0CE),
            ("export function Checkout() {", 0x90BCE9),
            ("  const [isSubmitting, setSubmitting] = useState(false);", 0xA8BED6),
            ("", 0xB5C0CE),
            ("  async function handleSubmit(values: CheckoutValues) {", 0x90BCE9),
            ("    setSubmitting(true);", 0xA8BED6),
            ("    await submitOrder(values);", 0xA8BED6),
            ("    setSubmitting(false);", 0xA8BED6),
            ("  }", 0xB5C0CE),
            ("", 0xB5C0CE),
            ("  return (", 0xBD9BDD),
            ("    <main className=\"checkout-layout\">", 0x88BBA1),
            ("      <CheckoutForm onSubmit={handleSubmit} />", 0x88BBA1),
            ("      <CartSummary pending={isSubmitting} />", 0x88BBA1),
            ("    </main>", 0x88BBA1),
            ("  );", 0xB5C0CE),
            ("}", 0xB5C0CE)
        ]
        for (index, line) in code.enumerated() {
            let y = 214 + CGFloat(index) * 23
            label(String(index + 1), x: 277, y: y, width: 30, size: 12, ink: secondary, mono: true)
            label(line.0, x: 319, y: y, width: 730, size: 12.5,
                  ink: dark ? color(line.1) : color(line.1 == 0x88BBA1 ? 0x34765E : line.1 == 0xBD9BDD ? 0x8455A8 : 0x3A648B), mono: true)
        }
        box(NSRect(x: 252, y: 699, width: 815, height: 142), color(dark ? 0x1C232D : 0xFAFBFC))
        label("终端      输出      问题", x: 276, y: 712, size: 11, weight: .medium, ink: secondary)
        let fail = number == 2
        label("$ npm run test -- checkout", x: 276, y: 744, size: 12, ink: fg, mono: true)
        label(fail ? "FAIL  tests/checkout.spec.ts  ·  request timed out" : "PASS  tests/checkout.spec.ts  ·  12 tests", x: 276, y: 770, size: 12,
              ink: color(fail ? (dark ? 0xF58287 : 0xBD3F51) : (dark ? 0x6ED6A1 : 0x27805B)), mono: true)
        label(fail ? "Waiting for retry configuration…" : "✓ Type check completed.  Watching for file changes…", x: 276, y: 797, size: 12, ink: secondary, mono: true)
        box(NSRect(x: 1067, y: 123, width: 489, height: 718), color(dark ? 0xEEF2F4 : 0xF7F9FA))
        box(NSRect(x: 1067, y: 123, width: 489, height: 44), color(dark ? 0xDDE4E8 : 0xEBEFF3))
        label("localhost:3000/checkout", x: 1155, y: 137, width: 310, size: 11, ink: color(0x566675))
        label("STOREFRONT", x: 1105, y: 202, size: 11, weight: .semibold, ink: color(0x51665F))
        label("确认你的订单", x: 1105, y: 246, size: 27, weight: .semibold, ink: color(0x243C35))
        label("本地开发预览", x: 1105, y: 289, size: 12, ink: color(0x71847B))
        box(NSRect(x: 1104, y: 341, width: 414, height: 160), .white, radius: 12)
        box(NSRect(x: 1123, y: 362, width: 100, height: 117), color(0xE0E9E3), radius: 7)
        symbol("bag", x: 1151, y: 409, width: 43, ink: color(0x7B9587))
        label("Canvas Tote", x: 1245, y: 373, width: 250, size: 17, weight: .medium, ink: color(0x304A3C))
        label("自然色  /  数量 1", x: 1245, y: 408, width: 250, size: 12, ink: color(0x71847B))
        label("¥ 129.00", x: 1245, y: 448, size: 17, weight: .semibold, ink: color(0x304A3C))
        label("收件信息", x: 1106, y: 540, size: 15, weight: .medium, ink: color(0x304A3C))
        for (index, title) in ["姓名", "配送地址", "联系电话"].enumerated() {
            let y = 582 + CGFloat(index) * 52
            box(NSRect(x: 1105, y: y, width: 412, height: 38), .white, radius: 6, border: color(0xD4DFD9))
            label(title, x: 1119, y: y + 10, size: 12, ink: color(0x819087))
        }
        box(NSRect(x: 1105, y: 750, width: 412, height: 45), color(0x426B58), radius: 8)
        label("提交订单", x: 1277, y: 764, size: 13, weight: .medium, ink: .white)
        box(NSRect(x: 44, y: 841, width: 1512, height: 25), color(dark ? 0x344B65 : 0xE4ECF5))
        label("main*      0 个错误    0 个警告", x: 65, y: 847, size: 10.5, ink: fg)
        label("TypeScript React    UTF-8    Ln 16, Col 42", x: 1190, y: 847, width: 350, size: 10.5, ink: fg)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawCaption() {
        let titles = ["并行处理多个任务", "右键查看对应会话的完整进度", "把字号与显示宽度调到顺手"]
        let subtitles = ["继续留在工作窗口，菜单栏同时保留每个会话的状态。", "错误红灯常亮；运行与完成条目继续保留，可分别查看。", "真实设置视图：字号、条目宽度、主题与展开数量即时预览。"]
        let fg = color(dark ? 0xF3F7FC : 0x203744)
        let muted = color(dark ? 0xC4D2DF : 0x435D6A)
        label(String(format: "%02d", number), x: 48, y: 920, width: 60, size: 20, weight: .medium, ink: muted, mono: true)
        label(titles[number - 1], x: 104, y: 912, width: 1050, size: 25, weight: .semibold, ink: fg)
        label(subtitles[number - 1], x: 104, y: 953, width: 1110, size: 14, ink: muted)
    }
}

func sampleSessions(error: Bool) -> [Session] {
    [Session(id: "sample-checkout", turnID: "sample", title: "结算页重构", status: .running,
             summary: "已调整表单布局，正在检查窄屏下的输入与提交状态。", updatedAt: fixedTime,
             startedAt: fixedTime.addingTimeInterval(-192)),
     Session(id: "sample-tests", turnID: "sample", title: "接口测试", status: error ? .failed : .running,
             summary: error ? "接口测试请求超时，本轮检查未完成。结算请求在 10 秒内未收到响应，已停止本轮测试。进入会话检查本地服务和测试配置后，再重试。" : "正在核对结算接口的边界条件，并执行回归测试。", updatedAt: fixedTime),
     Session(id: "sample-docs", turnID: "sample", title: "文档更新", status: .completed,
             summary: "已补充结算流程、错误状态说明与本地运行步骤。", updatedAt: fixedTime)]
}

func renderScenario(number: Int, dark: Bool, to file: String) throws {
    application.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let canvas = ScenarioCanvas(dark: dark, number: number)
    canvas.selectedPanel = number == 2
    canvas.settings = number == 3
    let window = NSWindow(contentRect: canvas.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = canvas
    var preferences = MenuPreferences()
    preferences.theme = dark ? .dark : .light
    preferences.cardWidth = 260
    preferences.menuFontSize = number == 3 ? 13 : 11.5
    preferences.detailFontSize = number == 3 ? 16 : 14
    preferences.scrolling = false
    preferences.animateLamps = false
    let sessions = sampleSessions(error: number == 2)
    for (index, session) in sessions.enumerated() {
        let badge = SessionBadgeView(session: session, width: 260, height: 28)
        badge.apply(preferences)
        badge.frame.origin = NSPoint(x: 540 + CGFloat(index) * 264, y: 1)
        canvas.addSubview(badge)
    }
    var detail: SessionDetailViewController?
    var host: NSHostingController<MenuSettingsView>?
    var model: PreferencesModel?
    var login: LoginItemModel?
    if number == 2 {
        let controller = SessionDetailViewController(session: sessions[1])
        _ = controller.view
        controller.apply(preferences)
        controller.update(sessions[1])
        controller.lamp.update(sessions[1].status, motionAllowed: false)
        let panel = controller.view
        panel.frame.origin = NSPoint(x: 734, y: 49)
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 12
        panel.layer?.masksToBounds = true
        let surround = NSView(frame: panel.frame)
        surround.wantsLayer = true
        surround.layer?.cornerRadius = 12
        surround.layer?.backgroundColor = MenuPalette.panel(dark: dark).cgColor
        surround.shadow = NSShadow()
        surround.shadow?.shadowBlurRadius = 24
        surround.shadow?.shadowColor = color(0x000000, alpha: 0.35)
        surround.shadow?.shadowOffset = NSSize(width: 0, height: -10)
        canvas.addSubview(surround)
        canvas.addSubview(panel)
        detail = controller
        // A small native-shaped pointer connects the card to the second badge.
        let arrow = PointerView(frame: NSRect(x: 925, y: 40, width: 18, height: 10), dark: dark)
        canvas.addSubview(arrow)
        let frame = panel.frame
        let geometry: [String: Double] = ["x": frame.minX, "y": frame.minY,
                                           "width": frame.width, "height": frame.height]
        try JSONSerialization.data(withJSONObject: geometry, options: [.sortedKeys])
            .write(to: output.appendingPathComponent("02-context-panel.json"))
    }
    if number == 3 {
        let settingsModel = PreferencesModel(preferences)
        let previewLogin = LoginItemModel(preview: true)
        let controller = NSHostingController(rootView: MenuSettingsView(model: settingsModel, login: previewLogin, onDone: {}))
        controller.view.frame = NSRect(x: 520, y: 110, width: 560, height: 720)
        controller.view.wantsLayer = true
        controller.view.layer?.cornerRadius = 12
        controller.view.layer?.masksToBounds = true
        canvas.addSubview(controller.view)
        host = controller
        model = settingsModel
        login = previewLogin
    }
    canvas.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    canvas.layoutSubtreeIfNeeded()
    detail?.refreshColors()
    guard let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else {
        throw StoreFailure(message: "Unable to render scenario")
    }
    canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
    try data.write(to: output.appendingPathComponent(file))
    print(output.appendingPathComponent(file).path)
    withExtendedLifetime((window, detail, host, model, login)) {}
}

final class PointerView: NSView {
    let dark: Bool
    override var isFlipped: Bool { true }
    init(frame: NSRect, dark: Bool) { self.dark = dark; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: 10))
        path.line(to: NSPoint(x: 9, y: 0))
        path.line(to: NSPoint(x: 18, y: 10))
        path.close()
        MenuPalette.panel(dark: dark).setFill()
        path.fill()
    }
}

try renderScenario(number: 1, dark: false, to: "01-parallel-work.png")
try renderScenario(number: 2, dark: true, to: "02-context-preview.png")
try renderScenario(number: 3, dark: false, to: "03-display-settings.png")
