import SwiftUI

struct ContentView: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Resizer").font(.headline)
                Spacer()
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Refresh window list")
            }

            if !model.trusted {
                permissionBox
            } else {
                sizeSection
                Divider()
                windowList
                applyBar
            }

            Divider()
            footer
        }
        .padding(Self.padding)
        .frame(width: Self.panelWidth)
        .onAppear { model.refresh() }
    }

    // MARK: Sections

    private var permissionBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Accessibility permission required", systemImage: "lock.shield")
                .font(.subheadline.bold())
            Text("To resize other apps' windows, enable Resizer in System Settings → Privacy & Security → Accessibility.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Request Permission") { WindowManager.requestPermission() }
                Button("Open Settings") { WindowManager.openAccessibilitySettings() }
            }
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // 3-column grid shared by the fields, the Save button and the presets.
    private static let boxWidth: CGFloat = 104
    private static let boxHeight: CGFloat = 26
    private static let gap: CGFloat = 12
    private static let padding: CGFloat = 14
    private static let panelWidth = boxWidth * 3 + gap * 2 + padding * 2

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

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Global shortcut: ⇧⌥R applies the current size to the focused window.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Center on screen", isOn: $model.center)
                .font(.caption).controlSize(.small)
            HStack {
                Toggle("Open at Login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .font(.caption).controlSize(.small)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless).font(.caption)
            }
        }
    }

    private var allSelected: Bool {
        !model.windows.isEmpty && model.selection.count == model.windows.count
    }
}
