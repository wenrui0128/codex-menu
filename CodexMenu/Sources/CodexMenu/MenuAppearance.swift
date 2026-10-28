import AppKit
import QuartzCore

enum MenuPalette {
    struct BadgeColors {
        let background: NSColor
        let foreground: NSColor
        let secondary: NSColor
        let border: NSColor
    }

    static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    static func surface(dark: Bool) -> NSColor { color(dark ? 0x444850 : 0xF4F5F7) }
    static func panel(dark: Bool) -> NSColor { color(dark ? 0x3D4148 : 0xFAFBFC) }
    static func foreground(dark: Bool) -> NSColor { color(dark ? 0xF4F5F7 : 0x252A32) }
    static func secondary(dark: Bool) -> NSColor { color(dark ? 0xD0D5DE : 0x555E6C) }
    static func border(dark: Bool) -> NSColor {
        dark ? NSColor.white.withAlphaComponent(0.13) : color(0xC9CFD8).withAlphaComponent(0.8)
    }

    static func badgeColors(preferences: MenuPreferences, appearance: NSAppearance) -> BadgeColors {
        let dark: Bool
        switch preferences.theme {
        case .light: dark = false
        case .dark: dark = true
        case .system: dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        if preferences.customColors {
            let text = color(preferences.textHex)
            return BadgeColors(background: color(preferences.backgroundHex).withAlphaComponent(preferences.backgroundOpacity),
                               foreground: text, secondary: text, border: text.withAlphaComponent(0.14))
        }
        // Follow the actual menu bar material, including wallpaper-dependent contrast.
        let background: NSColor = preferences.theme == .system ? .clear : surface(dark: dark).withAlphaComponent(0.94)
        return BadgeColors(background: background, foreground: foreground(dark: dark),
                           secondary: secondary(dark: dark), border: border(dark: dark))
    }

    static func lamp(for status: SessionStatus, dark: Bool) -> NSColor {
        switch status {
        case .running, .waiting, .interrupted: return color(dark ? 0xF5C451 : 0xB77A12)
        case .completed: return color(dark ? 0x6ED6A1 : 0x21865B)
        case .failed: return color(dark ? 0xF58287 : 0xC74350)
        case .unknown: return color(dark ? 0xB1BAC7 : 0x737F90)
        }
    }

    static func pulsePeriod(for status: SessionStatus) -> CFTimeInterval? {
        switch status {
        case .running: return 1.6
        case .completed: return 2.0
        default: return nil
        }
    }
}

/// A composited outline breathes around one native conversation button.
/// It stays visible when text scrolling pauses and never takes mouse events.
final class StatusOutlineView: NSView {
    private let glow = CAShapeLayer()
    private let stroke = CAShapeLayer()
    private(set) var status: SessionStatus
    private var pulsing = false

    init(status: SessionStatus) {
        self.status = status
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(false)
        for shape in [glow, stroke] {
            shape.fillColor = NSColor.clear.cgColor
            layer?.addSublayer(shape)
        }
        glow.lineWidth = 3.5
        stroke.lineWidth = 1
        update(status)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = CGPath(roundedRect: bounds.insetBy(dx: 2.25, dy: 2.75),
                          cornerWidth: 5.5, cornerHeight: 5.5, transform: nil)
        for shape in [glow, stroke] {
            shape.frame = bounds
            shape.path = path
        }
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    func update(_ value: SessionStatus, motionAllowed: Bool = true,
                reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        let changed = status != value
        status = value
        refreshColors()
        let shouldPulse = motionAllowed && !reduceMotion && MenuPalette.pulsePeriod(for: value) != nil
        guard changed || shouldPulse != pulsing else { return }
        pulsing = shouldPulse
        stroke.removeAllAnimations()
        glow.removeAllAnimations()
        guard shouldPulse, let period = MenuPalette.pulsePeriod(for: value) else { return }
        let pulse = CAKeyframeAnimation(keyPath: "opacity")
        pulse.values = [0.9, 0.28, 0.9]
        pulse.keyTimes = [0, 0.5, 1]
        pulse.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        pulse.duration = period
        pulse.repeatCount = .infinity
        stroke.add(pulse, forKey: "statusPulse")
        let halo = pulse.copy() as! CAKeyframeAnimation
        halo.values = [0.2, 0.03, 0.2]
        glow.add(halo, forKey: "statusPulse")
    }

    private func refreshColors() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color = MenuPalette.lamp(for: status, dark: dark)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stroke.strokeColor = color.cgColor
        glow.strokeColor = color.cgColor
        stroke.opacity = status == .unknown ? 0.35 : 0.72
        glow.opacity = 0.12
        CATransaction.commit()
    }

    var isPulsing: Bool { stroke.animation(forKey: "statusPulse") != nil }
}

/// A separate composited lamp keeps pulsing even when the progress text is paused.
final class StatusLampView: NSView {
    private let halo = CALayer()
    private let bulb = CALayer()
    private(set) var status: SessionStatus
    private var pulsing = false

    init(status: SessionStatus) {
        self.status = status
        super.init(frame: NSRect(x: 0, y: 0, width: 12, height: 12))
        wantsLayer = true
        setAccessibilityElement(false)
        layer?.addSublayer(halo)
        layer?.addSublayer(bulb)
        update(status)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        halo.frame = bounds.insetBy(dx: 0.5, dy: 0.5)
        halo.cornerRadius = halo.bounds.width / 2
        bulb.frame = bounds.insetBy(dx: 3, dy: 3)
        bulb.cornerRadius = bulb.bounds.width / 2
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    func update(_ value: SessionStatus, motionAllowed: Bool = true,
                reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        let changed = status != value
        status = value
        refreshColors()
        let shouldPulse = motionAllowed && !reduceMotion && MenuPalette.pulsePeriod(for: value) != nil
        guard changed || shouldPulse != pulsing else { return }
        pulsing = shouldPulse
        bulb.removeAllAnimations()
        halo.removeAllAnimations()
        guard shouldPulse, let period = MenuPalette.pulsePeriod(for: value) else { return }
        let pulse = CAKeyframeAnimation(keyPath: "opacity")
        pulse.values = [1, 0.3, 1]
        pulse.keyTimes = [0, 0.5, 1]
        pulse.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        pulse.duration = period
        pulse.repeatCount = .infinity
        bulb.add(pulse, forKey: "statusPulse")
        let glow = pulse.copy() as! CAKeyframeAnimation
        glow.values = [0.25, 0.08, 0.25]
        halo.add(glow, forKey: "statusPulse")
    }

    private func refreshColors() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color = MenuPalette.lamp(for: status, dark: dark)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bulb.backgroundColor = color.cgColor
        halo.backgroundColor = color.cgColor
        bulb.opacity = 1
        halo.opacity = 0.2
        CATransaction.commit()
    }

    var isPulsing: Bool { bulb.animation(forKey: "statusPulse") != nil }

    static func menuImage(for status: SessionStatus) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let color = MenuPalette.lamp(for: status, dark: dark)
            color.withAlphaComponent(0.18).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4)).fill()
            return true
        }
    }
}

final class MenuPanelSurface: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        MenuPalette.panel(dark: dark).setFill()
        bounds.fill()
    }
}

final class MenuHeaderView: NSView {
    init(running: Int, retained: Int, demo: Bool, fontSize: Double = 13) {
        let titleSize = max(13, fontSize)
        let subtitleSize = max(11, fontSize - 2)
        let height = ceil(titleSize + subtitleSize + 30)
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: height))
        let title = NSTextField(labelWithString: demo ? "Codex Menu · 演示" : "Codex Menu")
        title.font = .systemFont(ofSize: titleSize, weight: .semibold)
        title.frame = NSRect(x: 14, y: height - titleSize - 12, width: 370, height: titleSize + 4)
        let subtitle = NSTextField(labelWithString: "\(running) 个进行中   ·   \(retained) 个保留")
        subtitle.font = .systemFont(ofSize: subtitleSize)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 14, y: 9, width: 370, height: subtitleSize + 4)
        addSubview(title)
        addSubview(subtitle)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
