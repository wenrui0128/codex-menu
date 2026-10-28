import AppKit
import SwiftUI
import ServiceManagement

extension MenuTheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

final class PreferencesModel: ObservableObject {
    @Published private(set) var preferences: MenuPreferences
    var onChange: ((MenuPreferences) -> Void)?

    init(_ preferences: MenuPreferences) { self.preferences = preferences.normalized }

    func binding<Value>(_ keyPath: WritableKeyPath<MenuPreferences, Value>) -> Binding<Value> {
        Binding(get: { self.preferences[keyPath: keyPath] }, set: {
            var next = self.preferences
            next[keyPath: keyPath] = $0
            self.replace(next)
        })
    }

    func colorBinding(_ keyPath: WritableKeyPath<MenuPreferences, UInt32>) -> Binding<Color> {
        Binding(get: { Color(nsColor: MenuPalette.color(self.preferences[keyPath: keyPath])) }, set: {
            guard let color = NSColor($0).usingColorSpace(.sRGB) else { return }
            var next = self.preferences
            let red = UInt32((min(1, max(0, color.redComponent)) * 255).rounded())
            let green = UInt32((min(1, max(0, color.greenComponent)) * 255).rounded())
            let blue = UInt32((min(1, max(0, color.blueComponent)) * 255).rounded())
            next[keyPath: keyPath] = red << 16 | green << 8 | blue
            self.replace(next)
        })
    }

    func replace(_ preferences: MenuPreferences, notify: Bool = true) {
        self.preferences = preferences.normalized
        if notify { onChange?(self.preferences) }
    }
}

final class LoginItemModel: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var message: String?
    private let preview: Bool

    init(preview: Bool = false) { self.preview = preview; refresh() }

    func refresh() {
        guard !preview else { return }
        let status = SMAppService.mainApp.status
        enabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    func setEnabled(_ value: Bool) {
        guard !preview else { enabled = value; return }
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            message = nil
        } catch { message = "无法更新登录项：\(error.localizedDescription)" }
        refresh()
    }
}

private struct BadgePreview: NSViewRepresentable {
    let preferences: MenuPreferences

    func makeNSView(context: Context) -> SessionBadgeView {
        SessionBadgeView(session: sample, width: preferences.cardWidth, height: 28)
    }

    func updateNSView(_ view: SessionBadgeView, context: Context) {
        view.apply(preferences)
        // A stable preview makes font and width changes easy to compare.
        view.scrolling = false
    }

    private var sample: Session {
        Session(id: "settings-preview", turnID: "preview", title: "界面优化", status: .running,
                summary: "正在调整文字和布局", updatedAt: Date())
    }
}

struct MenuSettingsView: View {
    @ObservedObject var model: PreferencesModel
    @ObservedObject var login: LoginItemModel
    var onDone: () -> Void
    @State private var selectedTab = 0

    init(model: PreferencesModel, login: LoginItemModel, onDone: @escaping () -> Void, initialTab: Int = 0) {
        self.model = model
        self.login = login
        self.onDone = onDone
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Group {
                    if let icon = AppArtwork.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    } else {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 23, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Codex Menu 设置").font(.system(size: 18, weight: .semibold))
                    Text("调整后即时生效，并在下次启动时保留。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)

            HStack(spacing: 2) {
                tabButton("显示", index: 0)
                tabButton("颜色与外观", index: 1)
                tabButton("交互与启动", index: 2)
            }
            .padding(3)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .padding(.bottom, 8)

            Group {
                if selectedTab == 0 { displayTab }
                else if selectedTab == 1 { appearanceTab }
                else { behaviorTab }
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 16)

            Divider().padding(.top, 12)
            HStack {
                Button("恢复显示默认值") { model.replace(MenuPreferences()) }
                    .help("恢复字体、宽度、主题和动效设置；保留所有会话及登录项。")
                Spacer()
                Text("自动保存").font(.system(size: 11)).foregroundStyle(.secondary)
                Button("完成", action: onDone)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(model.preferences.theme.colorScheme)
    }

    private func tabButton(_ title: String, index: Int) -> some View {
        Button { selectedTab = index } label: {
            Text(title)
                .font(.system(size: 12, weight: selectedTab == index ? .medium : .regular))
                .foregroundStyle(selectedTab == index ? Color.primary : Color.secondary)
                .frame(width: 112, height: 27)
                .background {
                    if selectedTab == index {
                        RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedTab == index ? .isSelected : [])
    }

    private var badgePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("菜单栏预览").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            HStack {
                Spacer(minLength: 0)
                BadgePreview(preferences: model.preferences)
                    .frame(width: model.preferences.cardWidth, height: 28)
                    .accessibilityLabel("运行中的示例会话，仅用于预览")
                Spacer(minLength: 0)
            }
            .frame(height: 44)
            .background(model.preferences.cutoutText ? Color(nsColor: MenuPalette.color(0x52615D)) : Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 16).padding(.top, 16)
    }

    private var displayTab: some View {
        VStack(spacing: 0) {
            badgePreview

            Form {
                Section("文字") {
                    valueSlider("菜单栏字号", value: model.binding(\.menuFontSize), range: 10...15, step: 0.5, suffix: " pt")
                    valueSlider("进度卡片字号", value: model.binding(\.detailFontSize), range: 11...20, step: 0.5, suffix: " pt")
                    Text("会话列表与进度卡片随字号调整布局。菜单栏高度由 macOS 决定。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Section("布局") {
                    valueSlider("每个会话宽度", value: model.binding(\.cardWidth), range: 180...480, step: 20, suffix: " pt")
                    Stepper(value: model.binding(\.maxVisible), in: 1...6) {
                        HStack { Text("最多展开会话"); Spacer(); Text("\(model.preferences.maxVisible) 条").monospacedDigit().foregroundStyle(.secondary) }
                    }
                    Text("菜单栏空间不足时，其余会话仍可从总入口打开。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }

    private var appearanceTab: some View {
        VStack(spacing: 0) {
            badgePreview
            Form {
                Section("外观") {
                    Picker("外观", selection: model.binding(\.theme)) {
                        ForEach(MenuTheme.allCases) { Text($0.label).tag($0) }
                    }
                    Text("默认使用白底镂空文字，文字处透出菜单栏底色。窗口外观可跟随系统，或选择浅色和深色。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Section("菜单栏颜色") {
                    Toggle("镂空文字", isOn: model.binding(\.cutoutText))
                    Toggle("自定义菜单栏颜色", isOn: model.binding(\.customColors))
                    if model.preferences.customColors {
                        ColorPicker("底色", selection: model.colorBinding(\.backgroundHex), supportsOpacity: false)
                        ColorPicker("文字颜色", selection: model.colorBinding(\.textHex), supportsOpacity: false)
                            .disabled(model.preferences.cutoutText)
                        valueSlider("底色不透明度", value: Binding(get: { model.preferences.backgroundOpacity * 100 }, set: {
                            model.binding(\.backgroundOpacity).wrappedValue = $0 / 100
                        }), range: 0...100, step: 5, suffix: "%")
                        Text("仅调整菜单栏条目，状态光环保留黄、红、绿三色。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text(model.preferences.cutoutText ? "文字为透明镂空；关闭后可设置实色文字。" : "实色文字随所选外观调整，也可开启自定义颜色。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }

    private var behaviorTab: some View {
        Form {
            Section("会话显示") {
                Toggle("在会话按钮中显示标题", isOn: model.binding(\.showTitle))
                Toggle("在会话列表中显示运行计时", isOn: model.binding(\.showElapsed))
                Toggle("滚动显示公开进度", isOn: model.binding(\.scrolling))
                valueSlider("文字滚动速度", value: model.binding(\.scrollSpeed), range: 12...60, step: 4, suffix: " pt/s")
                    .disabled(!model.preferences.scrolling)
                Text("悬停时暂停文字。左键打开对应会话，右键查看完整公开进度。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("状态灯") {
                Toggle("会话边框呼吸光", isOn: model.binding(\.animateLamps))
                Text("运行：黄色呼吸光　完成：绿色呼吸光\n错误：红色常亮　等待：黄色常亮")
                    .font(.system(size: 12)).lineSpacing(4).foregroundStyle(.secondary)
                Text("光环沿整个会话条目显示，左侧圆点保留状态颜色。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text("系统开启“减少动态效果”时，文字和状态灯均保持静止。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("启动") {
                Toggle("登录后启动 Codex Menu", isOn: Binding(get: { login.enabled }, set: { login.setEnabled($0) }))
                if login.needsApproval {
                    Text("需要在系统设置中允许此登录项。").font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("打开登录项设置") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let message = login.message { Text(message).font(.system(size: 11)).foregroundStyle(.red).textSelection(.enabled) }
            }
        }
        .formStyle(.grouped)
        .onAppear { login.refresh() }
    }

    private func valueSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(0...1))) + suffix)
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step) { Text(title) }
                .labelsHidden()
                .accessibilityValue(value.wrappedValue.formatted() + suffix)
        }
    }
}

final class SettingsWindowController: NSWindowController {
    let model: PreferencesModel
    private let login: LoginItemModel

    init(preferences: MenuPreferences, demo: Bool) {
        model = PreferencesModel(preferences)
        login = LoginItemModel(preview: demo)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Codex Menu 设置"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("CodexMenu.settings")
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: MenuSettingsView(model: model, login: login, onDone: { [weak self] in self?.close() }))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(preferences: MenuPreferences, onChange: @escaping (MenuPreferences) -> Void) {
        model.replace(preferences, notify: false)
        window?.appearance = preferences.theme.appearance
        model.onChange = onChange
        login.refresh()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
