import SwiftUI

struct ContentView: View {
    @ObservedObject var model: Model
    @ObservedObject var zone: StreamZone

    @AppStorage("settingsTab") private var tab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.trusted { permissionBox }
            TabView(selection: $tab) {
                zoneTab.tabItem { Text("Stream Zone") }.tag(0)
                resizeTab.tabItem { Text("Resize Windows") }.tag(1)
                generalTab.tabItem { Text("General") }.tag(2)
            }
        }
        .padding(20)
        .frame(width: 520, height: model.trusted ? 600 : 700)
        .onAppear { model.refresh() }
    }

    // MARK: Tabs

    private var zoneTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("Frame") {
                Toggle("Show a frame around the zone", isOn: $zone.visible)
                row("Color") { colorSwatches }
                Toggle("Dim everything outside the zone", isOn: $zone.dimOutside)
            }

            group("Zone") {
                row("Screen") {
                    Picker("Screen", selection: zoneScreen) {
                        Text("Widest screen").tag(StreamZone.autoScreen)
                        Divider()
                        ForEach(zone.screens, id: \.id) { s in Text(s.name).tag(s.id) }
                    }
                    .labelsHidden().fixedSize()
                }
                row("Size") {
                    Picker("Size", selection: zoneSize) {
                        ForEach(zone.sizeOptions, id: \.self) { s in Text(zone.label(for: s)).tag(s) }
                    }
                    .labelsHidden().fixedSize()
                }
                row("On stream") {
                    Text(verbatim: "\(Int(zone.pixelSize.width)) × \(Int(zone.pixelSize.height)) px")
                        .monospacedDigit()
                }
                let c = zone.crop
                row("OBS crop") {
                    Text(verbatim: "Left \(c.left) · Right \(c.right) · Top \(c.top) · Bottom \(c.bottom)")
                        .monospacedDigit().textSelection(.enabled)
                }
            }

            group("Windows") {
                Toggle("Snap windows dropped in the zone", isOn: $zone.snapOnDrop)
                Text("Drop a window in the middle of the zone to fill it, or near its left or right edge to take that half.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                shortcut("⌃⌥⌘↑", "Focused window fills the zone")
                shortcut("⌃⌥⌘←", "Focused window takes the left half")
                shortcut("⌃⌥⌘→", "Focused window takes the right half")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var resizeTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.trusted {
                sizeSection
                Toggle("Center on screen", isOn: $model.center)
                Divider()
                windowList
                applyBar
            } else {
                Text("Needs the Accessibility permission (see above).")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            shortcut("⇧⌥R", "Applies the size above to the focused window")
        }
        .padding(16)
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("Startup") {
                Toggle("Open at Login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }
            group("Accessibility") {
                HStack {
                    Image(systemName: model.trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.trusted ? Color.green : .orange)
                    Text(model.trusted ? "Permission granted" : "Permission missing")
                    Spacer()
                    Button("Open Settings") { WindowManager.openAccessibilitySettings() }
                }
            }
            group("Menu bar icon") {
                Text("Click to open this window. Right-click for quick toggles and Quit.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !model.status.isEmpty {
                Text(model.status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Quit Resizer") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
    }

    // MARK: Pieces

    private var permissionBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Accessibility permission required", systemImage: "lock.shield")
                .font(.subheadline.bold())
            Text("Snapping and resizing need Resizer turned on in System Settings → Privacy & Security → Accessibility. If it's already on there but this message stays, that entry is from an older build: click Reset Permission and turn it on again.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Reset Permission") { WindowManager.resetPermission() }
                Button("Open Settings") { WindowManager.openAccessibilitySettings() }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var colorSwatches: some View {
        HStack(spacing: 10) {
            ForEach(StreamZone.FrameColor.allCases) { c in
                let selected = zone.color == c
                Button { zone.color = c } label: {
                    Circle()
                        .fill(Color(nsColor: c.nsColor))
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 0.5))
                        .padding(3)
                        .overlay(Circle().stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .help(c.name)
            }
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold()).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Text(label).frame(width: 80, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func shortcut(_ keys: String, _ what: String) -> some View {
        HStack {
            Text(keys).font(.callout.monospaced()).frame(width: 70, alignment: .leading)
            Text(what).font(.callout).foregroundStyle(.secondary)
        }
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

    // 3-column grid shared by the fields, the Save button and the presets.
    private static let boxWidth: CGFloat = 104
    private static let boxHeight: CGFloat = 26
    private static let gap: CGFloat = 12

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                numberField("Width", text: $model.width, max: model.maxWidth)
                Text("×").font(.caption).foregroundStyle(.secondary)
                    .frame(width: Self.gap)
                numberField("Height", text: $model.height, max: model.maxHeight)
                Color.clear.frame(width: Self.gap, height: 1)
                saveBox
            }

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.boxWidth), spacing: Self.gap), count: 3),
                      alignment: .leading, spacing: 8) {
                ForEach(model.presets, id: \.self) { p in presetBox(p) }
            }

            Text("Max for this screen: \(model.maxWidth)×\(model.maxHeight)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var saveBox: some View {
        let enabled = model.targetSize != nil && model.activePreset == nil
        return Button { model.saveCurrentAsPreset() } label: {
            Text("Save Preset")
                .font(.callout.weight(.semibold))
                .frame(width: Self.boxWidth, height: Self.boxHeight)
                .foregroundStyle(enabled ? Color.white : .secondary)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(enabled ? Color.accentColor : Color.secondary.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(enabled ? Color.accentColor : Color.secondary.opacity(0.35)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// Numbers-only field, capped at the screen resolution.
    private func numberField(_ placeholder: String, text: Binding<String>, max: Int) -> some View {
        NumericField(placeholder: placeholder, text: text, max: max)
        .padding(.horizontal, 6)
        .frame(width: Self.boxWidth, height: Self.boxHeight)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.35)))
    }

    private func presetBox(_ p: String) -> some View {
        let active = model.activePreset == p
        let fits = model.fits(p)
        return Button { model.choosePreset(p) } label: {
            HStack(spacing: 4) {
                if active { Image(systemName: "checkmark").font(.caption.bold()) }
                Text(p.replacingOccurrences(of: "x", with: "×"))
                    .font(.callout.monospacedDigit())
            }
            .frame(width: Self.boxWidth, height: Self.boxHeight)
            .foregroundStyle(active ? Color.white : .primary)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(active ? Color.accentColor : Color.secondary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(active ? Color.accentColor : Color.secondary.opacity(0.35)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!fits)
        .opacity(fits ? 1 : 0.4)
        .help(fits ? "" : "Larger than the current screen")
        .contextMenu {
            Button("Delete Preset", role: .destructive) { model.removePreset(p) }
        }
    }

    private var windowList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Open Windows").font(.subheadline.bold())
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Refresh window list")
                Spacer()
                Button(allSelected ? "Deselect All" : "Select All") {
                    model.selection = allSelected ? [] : Set(model.windows.map(\.id))
                }
                .buttonStyle(.borderless).font(.caption)
            }

            if model.windows.isEmpty {
                Text("No windows found.").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.windows) { win in row(win) }
                    }
                }
                .frame(height: min(CGFloat(model.windows.count) * 38 + 4, 260))
            }
        }
    }

    private func row(_ win: WindowItem) -> some View {
        let selected = model.selection.contains(win.id)
        return Button {
            if selected { model.selection.remove(win.id) } else { model.selection.insert(win.id) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                if let icon = win.icon {
                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(win.appName).font(.callout).lineLimit(1)
                    Text(win.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(win.isFullScreen ? "full screen" : "\(Int(win.size.width))×\(Int(win.size.height))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(selected ? Color.accentColor.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var applyBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                model.applyToSelected()
            } label: {
                Text(model.selection.isEmpty
                     ? "Apply"
                     : "Apply to \(model.selection.count) window(s)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.selection.isEmpty || model.targetSize == nil)

            if !model.status.isEmpty {
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var allSelected: Bool {
        !model.windows.isEmpty && model.selection.count == model.windows.count
    }
}
