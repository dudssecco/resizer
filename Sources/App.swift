import SwiftUI
import ServiceManagement
import Carbon.HIToolbox

@main
struct ResizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    // The menu bar icon and the settings window are managed by AppDelegate.
    var body: some Scene { Settings { EmptyView() } }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKey.register(kVK_ANSI_R, shiftKey | optionKey) { Model.shared.applyToFocusedWindow() }
        let zoneKeys = controlKey | optionKey | cmdKey
        HotKey.register(kVK_UpArrow, zoneKeys) { StreamZone.shared.sendFocused(.full) }
        HotKey.register(kVK_LeftArrow, zoneKeys) { StreamZone.shared.sendFocused(.left) }
        HotKey.register(kVK_RightArrow, zoneKeys) { StreamZone.shared.sendFocused(.right) }
        StreamZone.shared.start()
        setUpStatusItem()
        if !WindowManager.isTrusted { WindowManager.requestPermission() }
    }

    // MARK: Menu bar icon: left click opens settings, right click shows the menu

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Resizer")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            showSettings()
        }
    }

    private func showMenu() {
        let zone = StreamZone.shared, model = Model.shared
        let menu = NSMenu()
        menu.addItem(item("Open Resizer…", #selector(showSettings)))
        menu.addItem(.separator())
        menu.addItem(item("Show Zone Frame", #selector(toggleFrame), on: zone.visible))
        menu.addItem(item("Snap Windows to Zone", #selector(toggleSnap), on: zone.snapOnDrop))
        menu.addItem(.separator())
        menu.addItem(item("Open at Login", #selector(toggleLogin), on: model.launchAtLogin))
        menu.addItem(.separator())
        menu.addItem(item("Quit Resizer", #selector(quit), key: "q"))

        // Attach the menu only for this click so a left click keeps opening the window.
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    private func item(_ title: String, _ action: Selector, on: Bool? = nil, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        if let on { i.state = on ? .on : .off }
        return i
    }

    @objc private func toggleFrame() { StreamZone.shared.visible.toggle() }
    @objc private func toggleSnap() { StreamZone.shared.snapOnDrop.toggle() }
    @objc private func toggleLogin() { Model.shared.setLaunchAtLogin(!Model.shared.launchAtLogin) }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Settings window

    @objc func showSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: ContentView(model: .shared, zone: .shared))
            let window = NSWindow(contentViewController: host)
            window.title = "Resizer"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        Model.shared.refresh()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - State

final class Model: ObservableObject {
    static let shared = Model()

    @Published var width: String
    @Published var height: String
    @Published var center: Bool { didSet { defaults.set(center, forKey: "center") } }
    @Published var presets: [String] { didSet { defaults.set(presets, forKey: "presets") } }
    @Published var windows: [WindowItem] = []
    @Published var selection: Set<UUID> = []
    @Published var status = ""
    @Published var trusted = WindowManager.isTrusted
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// Current screen resolution (in points, the same unit windows use).
    @Published var maxSize = Model.currentScreenSize()

    private let defaults = UserDefaults.standard
    private var timer: Timer?

    static let defaultPresets = ["1280x720", "1366x768", "1440x900", "1600x900",
                                 "1920x1080", "2560x1440"]

    private init() {
        width = defaults.string(forKey: "width") ?? "1280"
        height = defaults.string(forKey: "height") ?? "720"
        center = defaults.object(forKey: "center") as? Bool ?? true
        presets = defaults.stringArray(forKey: "presets") ?? Self.defaultPresets

        // Keep the permission status fresh while the user is in System Settings.
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let t = WindowManager.isTrusted
            if t != self.trusted {
                self.trusted = t
                if t { self.refresh() }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.updateScreen() }
        updateScreen()
    }

    static let minSide = 100

    static func currentScreenSize() -> CGSize {
        (NSScreen.main ?? NSScreen.screens.first)?.frame.size ?? CGSize(width: 1920, height: 1080)
    }

    var maxWidth: Int { Int(maxSize.width) }
    var maxHeight: Int { Int(maxSize.height) }

    var targetSize: CGSize? {
        guard let w = Int(width), let h = Int(height),
              (Self.minSide...maxWidth).contains(w),
              (Self.minSide...maxHeight).contains(h) else { return nil }
        return CGSize(width: w, height: h)
    }

    /// Preset matching the typed values (shows the checkmark).
    var activePreset: String? {
        let p = "\(width)x\(height)"
        return presets.contains(p) ? p : nil
    }

    func fits(_ preset: String) -> Bool {
        guard let (w, h) = Self.parse(preset) else { return false }
        return w <= maxWidth && h <= maxHeight
    }

    /// Keeps digits only and caps at the screen size.
    func sanitize(_ text: String, max: Int) -> String {
        NumericField.Coordinator.sanitize(text, max: max)
    }

    func updateScreen() {
        maxSize = Self.currentScreenSize()
        width = sanitize(width, max: maxWidth)
        height = sanitize(height, max: maxHeight)
    }

    private static func parse(_ preset: String) -> (Int, Int)? {
        let parts = preset.split(separator: "x").compactMap { Int($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    func refresh() {
        updateScreen()
        trusted = WindowManager.isTrusted
        guard trusted else { windows = []; return }
        windows = WindowManager.listWindows()
        selection = selection.filter { id in windows.contains { $0.id == id } }
    }

    func choosePreset(_ p: String) {
        guard fits(p), let (w, h) = Self.parse(p) else { return }
        width = String(w); height = String(h)
    }

    func saveCurrentAsPreset() {
        guard let s = targetSize else { return }
        let p = "\(Int(s.width))x\(Int(s.height))"
        if !presets.contains(p) { presets.append(p) }
    }

    func removePreset(_ p: String) { presets.removeAll { $0 == p } }

    func applyToSelected() {
        guard let size = targetSize else {
            status = "Invalid size (min \(Self.minSide), max \(maxWidth)×\(maxHeight))."
            return
        }
        let targets = windows.filter { selection.contains($0.id) }
        guard !targets.isEmpty else { status = "Select at least one window."; return }
        remember()

        var ok = 0
        var notes: [String] = []
        for win in targets {
            switch WindowManager.resize(win.element, to: size, center: center) {
            case .ok: ok += 1
            case .limited(let s): notes.append("\(win.appName): ended up \(Int(s.width))×\(Int(s.height)) (app/screen limit)")
            case .failed(let why): notes.append("\(win.appName): \(why)")
            }
        }
        status = (["\(ok) of \(targets.count) window(s) resized to \(Int(size.width))×\(Int(size.height))."] + notes)
            .joined(separator: "\n")
        windows = WindowManager.listWindows()
        // Keep the selection (same app/title) after reloading.
        let keys = Set(targets.map { "\($0.pid)|\($0.title)" })
        selection = Set(windows.filter { keys.contains("\($0.pid)|\($0.title)") }.map(\.id))
    }

    func applyToFocusedWindow() {
        guard WindowManager.isTrusted else { WindowManager.requestPermission(); return }
        guard let size = targetSize, let w = WindowManager.focusedWindow() else { NSSound.beep(); return }
        if case .failed = WindowManager.resize(w, to: size, center: center) { NSSound.beep() }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            status = "Couldn't change \"Open at Login\": \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func remember() {
        defaults.set(width, forKey: "width")
        defaults.set(height, forKey: "height")
    }
}
