import SwiftUI
import AppKit

/// Settings window: a translucent "glass" window with three tabs.
struct ContentView: View {
    @ObservedObject var model: Model
    @ObservedObject var zone: StreamZone
    @AppStorage("settingsTab") private var tab = Tab.zone
    @Environment(\.colorScheme) private var scheme
    @State private var copiedCrop = false

    enum Tab: Int, CaseIterable {
        case zone, resize, general

        var title: String {
            switch self {
            case .zone: return "Stream Zone"
            case .resize: return "Resize Windows"
            case .general: return "General"
            }
        }

        var icon: String {
            switch self {
            case .zone: return "rectangle.center.inset.filled"
            case .resize: return "arrow.up.left.and.arrow.down.right"
            case .general: return "slider.horizontal.3"
            }
        }
    }

    private var g: Glass { Glass(dark: scheme == .dark) }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            VStack(alignment: .leading, spacing: 18) {
                if !model.trusted { permissionCard }
                switch tab {
                case .zone: zoneTab
                case .resize: resizeTab
                case .general: generalTab
                }
            }
            .padding(EdgeInsets(top: 14, leading: 22, bottom: 24, trailing: 22))
        }
        .frame(width: 620)
        .fixedSize(horizontal: false, vertical: true)
        .background(VisualEffectBackground().ignoresSafeArea())
        .onAppear { model.refresh() }
    }

    // MARK: Tab bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { t in
                let on = tab == t
                Button { tab = t } label: {
                    HStack(spacing: 7) {
                        Image(systemName: t.icon)
                            .foregroundStyle(on ? Color.accentColor : .secondary)
                        Text(t.title)
                            .foregroundStyle(on ? Color.primary : .secondary)
                    }
                    .font(.system(size: 13, weight: on ? .semibold : .medium))
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background {
                        if on {
                            Capsule().fill(g.tabOn)
                                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .modifier(GlassCapsule(fallback: g.seg, border: g.cardBorder))
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    // MARK: Stream Zone

    private var zoneTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Zone") {
                zonePreview
                    .padding(EdgeInsets(top: 18, leading: 14, bottom: 14, trailing: 14))
                separator
                row("Screen") {
                    Picker("Screen", selection: zoneScreen) {
                        Text("Widest screen").tag(StreamZone.autoScreen)
                        Divider()
                        ForEach(zone.screens, id: \.id) { s in Text(s.name).tag(s.id) }
                    }
                    .labelsHidden().fixedSize()
                }
                separator
                row("Size") {
                    Picker("Size", selection: zoneSize) {
                        ForEach(zone.sizeOptions, id: \.self) { s in Text(zone.label(for: s)).tag(s) }
                    }
                    .labelsHidden().fixedSize()
                }
                separator
                row("OBS crop", detail: "Display Capture → Crop, in pixels") { cropChips }
            }

            section("Frame") {
                row("Show frame", detail: "Drawn just outside the zone, never on stream") {
                    glassSwitch($zone.visible)
                }
                separator
                row("Color") { colorSwatches }
                separator
                row("Dim outside the zone") { glassSwitch($zone.dimOutside) }
            }

            section("Windows") {
                row("Snap on drop", detail: "Hold \(zone.snapKey.symbol) while dragging: middle fills the zone, near an edge takes that half") {
                    glassSwitch($zone.snapOnDrop)
                }
                separator
                row("Hold to snap", detail: "Without it, windows just move") {
                    Picker("Hold to snap", selection: $zone.snapKey) {
                        ForEach(StreamZone.SnapKey.allCases) { k in Text("\(k.symbol) \(k.name)").tag(k) }
                    }
                    .labelsHidden().fixedSize()
                }
                .disabled(!zone.snapOnDrop)
                separator
                HStack(spacing: 8) {
                    shortcutTile(["⌃", "⌥", "⌘", "↑"], "Fill the zone")
                    shortcutTile(["⌃", "⌥", "⌘", "←"], "Left half")
                    shortcutTile(["⌃", "⌥", "⌘", "→"], "Right half")
                }
                .padding(EdgeInsets(top: 10, leading: 14, bottom: 12, trailing: 14))
            }
        }
    }

    /// The zone's screen in miniature, with the zone in its frame color.
    private var zonePreview: some View {
        let screen = zone.screenFrame
        let scale = screen.width > 0 ? min(428 / screen.width, 150 / screen.height) : 0
        let z = zone.rect
        let zoneW = z.width * scale, zoneH = z.height * scale
        let zoneX = (z.minX - screen.minX) * scale, zoneY = (screen.maxY - z.maxY) * scale
        let color = Color(nsColor: zone.color.nsColor)

        return VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(g.screen)
                if zone.dimOutside {
                    Rectangle().fill(.black.opacity(0.5))
                        .mask {
                            ZStack(alignment: .topLeading) {
                                Rectangle()
                                RoundedRectangle(cornerRadius: 6).frame(width: zoneW, height: zoneH)
                                    .offset(x: zoneX, y: zoneY).blendMode(.destinationOut)
                            }
                            .compositingGroup()
                        }
                }
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(color, lineWidth: 2)
                    .shadow(color: color.opacity(0.6), radius: 5)
                    .overlay {
                        Text(verbatim: "\(Int(z.width)) × \(Int(z.height))")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    }
                    .frame(width: zoneW, height: zoneH)
                    .offset(x: zoneX, y: zoneY)
                    .opacity(zone.visible ? 1 : 0.45)
            }
            .frame(width: screen.width * scale, height: screen.height * scale)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(g.cardBorder))

            Text(verbatim: "\(zone.screenName) · \(Int(screen.width)) × \(Int(screen.height)) — the middle \(Int(z.width)) × \(Int(z.height)) goes on stream")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var cropChips: some View {
        let c = zone.crop
        return HStack(spacing: 6) {
            ForEach([("L", c.left), ("R", c.right), ("T", c.top), ("B", c.bottom)], id: \.0) { side, value in
                HStack(spacing: 3) {
                    Text(side).foregroundStyle(.secondary)
                    Text(verbatim: "\(value)")
                }
                .font(.system(size: 12).monospacedDigit())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(g.control))
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("Left \(c.left), Right \(c.right), Top \(c.top), Bottom \(c.bottom)",
                                               forType: .string)
                copiedCrop = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedCrop = false }
            } label: {
                Image(systemName: copiedCrop ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(g.control))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(g.controlBorder))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy crop values")
        }
    }

    private var colorSwatches: some View {
        HStack(spacing: 12) {
            ForEach(StreamZone.FrameColor.allCases) { c in
                let selected = zone.color == c
                Button { zone.color = c } label: {
                    Circle()
                        .fill(Color(nsColor: c.nsColor))
                        .overlay(Circle().strokeBorder(.black.opacity(0.18)))
                        .frame(width: 22, height: 22)
                        .padding(3)
                        .overlay(Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(c.name)
            }
        }
    }

    private func shortcutTile(_ keys: [String], _ what: String) -> some View {
        VStack(spacing: 6) {
            keycaps(keys)
            Text(what).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(g.control))
    }

    // MARK: Resize Windows

    private var resizeTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Size") {
                HStack(alignment: .bottom, spacing: 10) {
                    numberField("Width", text: $model.width, max: model.maxWidth)
                    Text("×").font(.system(size: 15)).foregroundStyle(.secondary).frame(height: 34)
                    numberField("Height", text: $model.height, max: model.maxHeight)
                    Button { model.saveCurrentAsPreset() } label: {
                        Text("Save preset").font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(g.control))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(g.controlBorder))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.targetSize == nil || model.activePreset != nil)
                }
                .padding(EdgeInsets(top: 14, leading: 14, bottom: 12, trailing: 14))

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(model.presets, id: \.self) { p in presetChip(p) }
                }
                .padding(EdgeInsets(top: 0, leading: 14, bottom: 14, trailing: 14))

                separator
                row("Center on screen") { glassSwitch($model.center) }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    sectionTitle("Open windows")
                    Spacer()
                    Button { model.refresh() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                            .frame(width: 26, height: 26).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Refresh window list")
                    Button(allSelected ? "Deselect all" : "Select all") {
                        model.selection = allSelected ? [] : Set(model.windows.map(\.id))
                    }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.trailing, 6)
                }
                card {
                    if model.windows.isEmpty {
                        Text(model.trusted ? "No windows found." : "Needs the Accessibility permission.")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(model.windows) { win in windowRow(win) }
                            }
                            .padding(4)
                        }
                        .frame(height: min(CGFloat(model.windows.count) * 48 + 8, 248))
                    }
                }
            }

            VStack(spacing: 10) {
                Button { model.applyToSelected() } label: {
                    Text(model.selection.isEmpty ? "Apply" : "Apply to \(model.selection.count) window\(model.selection.count == 1 ? "" : "s")")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(Capsule().fill(Color.accentColor))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 9, y: 6)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.selection.isEmpty || model.targetSize == nil)
                .opacity(model.selection.isEmpty || model.targetSize == nil ? 0.5 : 1)

                Text(model.status.isEmpty ? "⇧⌥R applies this size to the focused window" : model.status)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Numbers-only field, capped at the screen resolution.
    private func numberField(_ label: String, text: Binding<String>, max: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11.5)).foregroundStyle(.secondary)
            NumericField(placeholder: label, text: text, max: max, fontSize: 15)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(g.control))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(g.controlBorder))
        }
    }

    private func presetChip(_ p: String) -> some View {
        let active = model.activePreset == p
        let fits = model.fits(p)
        return Button { model.choosePreset(p) } label: {
            Text(p.replacingOccurrences(of: "x", with: "×"))
                .font(.system(size: 13, weight: active ? .semibold : .medium).monospacedDigit())
                .foregroundStyle(active ? Color.white : .primary)
                .frame(maxWidth: .infinity).frame(height: 32)
                .background(Capsule().fill(active ? Color.accentColor : g.control))
                .overlay(Capsule().strokeBorder(active ? Color.accentColor : g.controlBorder))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!fits)
        .opacity(fits ? 1 : 0.4)
        .help(fits ? "Right-click to delete" : "Larger than the current screen")
        .contextMenu {
            Button("Delete Preset", role: .destructive) { model.removePreset(p) }
        }
    }

    private func windowRow(_ win: WindowItem) -> some View {
        let selected = model.selection.contains(win.id)
        return Button {
            if selected { model.selection.remove(win.id) } else { model.selection.insert(win.id) }
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    Circle().strokeBorder(selected ? Color.accentColor : .secondary, lineWidth: 1.5)
                    if selected {
                        Circle().fill(Color.accentColor)
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 20, height: 20)
                if let icon = win.icon {
                    Image(nsImage: icon).resizable().frame(width: 30, height: 30)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(win.appName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(win.title).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(win.isFullScreen ? "full screen" : "\(Int(win.size.width)) × \(Int(win.size.height))")
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? g.selected : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var allSelected: Bool {
        !model.windows.isEmpty && model.selection.count == model.windows.count
    }

    // MARK: General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Startup") {
                row("Open at login", detail: "Resizer starts in the menu bar when you log in") {
                    glassSwitch(Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                }
            }

            section("Accessibility") {
                HStack(spacing: 12) {
                    Image(systemName: model.trusted ? "checkmark" : "exclamationmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(model.trusted ? Color.green : .orange)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill((model.trusted ? Color.green : .orange).opacity(0.18)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.trusted ? "Permission granted" : "Permission missing")
                            .font(.system(size: 13, weight: .medium))
                        Text(model.trusted ? "Resizer can move and resize other apps’ windows"
                                           : "Snapping, shortcuts and resizing won’t work")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !model.trusted {
                        capsuleButton("Reset Permission") { WindowManager.resetPermission() }
                    }
                    capsuleButton("Open Settings") { WindowManager.openAccessibilitySettings() }
                }
                .padding(.horizontal, 14).frame(minHeight: 56)
            }

            section("Keyboard shortcuts") {
                shortcutRow("Hold while dragging a window to snap it into the zone", [zone.snapKey.symbol])
                separator
                shortcutRow("Fill the zone with the focused window", ["⌃", "⌥", "⌘", "↑"])
                separator
                shortcutRow("Left half of the zone", ["⌃", "⌥", "⌘", "←"])
                separator
                shortcutRow("Right half of the zone", ["⌃", "⌥", "⌘", "→"])
                separator
                shortcutRow("Apply the saved size to the focused window", ["⇧", "⌥", "R"])
            }

            section("Menu bar icon") {
                row("Click") { Text("Opens this window").font(.system(size: 13)).foregroundStyle(.secondary) }
                separator
                row("Right-click") {
                    Text("Quick toggles, Open at login, Quit").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(verbatim: "Resizer \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button { NSApp.terminate(nil) } label: {
                    Text("Quit Resizer").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(nsColor: .systemRed))
                        .padding(.horizontal, 16).frame(height: 32)
                        .background(Capsule().fill(g.control))
                        .overlay(Capsule().strokeBorder(g.controlBorder))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 14).padding(.trailing, 4)
        }
    }

    private func shortcutRow(_ what: String, _ keys: [String]) -> some View {
        HStack {
            Text(what).font(.system(size: 13))
            Spacer()
            keycaps(keys)
        }
        .padding(.horizontal, 14).frame(minHeight: 44)
    }

    // MARK: Permission

    private var permissionCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 18)).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text("Accessibility permission required").font(.system(size: 13, weight: .semibold))
                Text("Snapping and resizing need Resizer turned on in System Settings → Privacy & Security → Accessibility. If it’s already on there, that entry is from an older build: click Reset Permission and turn it on again.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    capsuleButton("Reset Permission") { WindowManager.resetPermission() }
                    capsuleButton("Open Settings") { WindowManager.openAccessibilitySettings() }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.orange.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.orange.opacity(0.3)))
    }

    // MARK: Building blocks

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.leading, 14)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(g.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(g.cardBorder))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle(title)
            card(content)
        }
    }

    private func row<Content: View>(_ label: String, detail: String? = nil,
                                    @ViewBuilder _ control: () -> Content) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13))
                if let detail {
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(minHeight: 46)
    }

    private var separator: some View {
        Rectangle().fill(g.cardBorder).frame(height: 1)
    }

    private func glassSwitch(_ isOn: Binding<Bool>) -> some View {
        Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden().tint(.green)
    }

    private func keycaps(_ keys: [String]) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, k in
                Text(k).font(.system(size: 12, weight: .semibold))
                    .frame(minWidth: 22, minHeight: 20)
                    .padding(.horizontal, 2)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(g.control))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(g.controlBorder))
            }
        }
    }

    private func capsuleButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13))
                .padding(.horizontal, 12).frame(height: 30)
                .background(Capsule().fill(g.control))
                .overlay(Capsule().strokeBorder(g.controlBorder))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // A saved size or screen that doesn't apply here shows what's actually used.
    private var zoneSize: Binding<Int> {
        Binding(get: { zone.sizeOptions.contains(zone.size) ? zone.size : StreamZone.maxSize },
                set: { zone.size = $0 })
    }

    private var zoneScreen: Binding<CGDirectDisplayID> {
        Binding(get: { zone.screens.contains { $0.id == zone.screenID } ? zone.screenID : StreamZone.autoScreen },
                set: { zone.screenID = $0 })
    }
}

// MARK: - Glass styling

/// Translucent fills layered over the window's blurred background.
private struct Glass {
    let dark: Bool
    var card: Color { dark ? .white.opacity(0.06) : .white.opacity(0.55) }
    var cardBorder: Color { dark ? .white.opacity(0.08) : .black.opacity(0.06) }
    var control: Color { dark ? .white.opacity(0.10) : .white.opacity(0.8) }
    var controlBorder: Color { dark ? .white.opacity(0.12) : .black.opacity(0.10) }
    var seg: Color { dark ? .white.opacity(0.06) : .black.opacity(0.05) }
    var tabOn: Color { dark ? .white.opacity(0.16) : .white.opacity(0.95) }
    var selected: Color { Color.accentColor.opacity(dark ? 0.18 : 0.12) }
    var screen: Color { dark ? Color(white: 0.07) : Color(red: 0.79, green: 0.83, blue: 0.90) }
}

/// Liquid Glass capsule on macOS 26+, a translucent capsule before that.
private struct GlassCapsule: ViewModifier {
    let fallback: Color
    let border: Color

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(Capsule().fill(fallback))
                .overlay(Capsule().strokeBorder(border))
        }
    }
}

/// Blurs whatever is behind the window (the desktop, other windows).
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
