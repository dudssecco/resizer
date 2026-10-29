import AppKit
import ApplicationServices
import os

/// Read with: log show --last 10m --predicate 'subsystem == "io.github.dudssecco.Resizer"'
private let log = Logger(subsystem: "io.github.dudssecco.Resizer", category: "zone")

/// The 16:9 area in the middle of a screen that goes on stream.
/// OBS crops the display capture to it; windows snap into it.
final class StreamZone: ObservableObject {
    static let shared = StreamZone()
    /// Common 16:9 heights offered when they fit; `maxSize` is always offered too.
    static let heights = [540, 720, 900, 1080, 1440, 2160]
    static let maxSize = 0
    static let autoScreen: CGDirectDisplayID = 0

    enum Slot { case full, left, right }

    struct ScreenOption: Hashable {
        let id: CGDirectDisplayID
        let name: String
    }

    enum FrameColor: String, CaseIterable, Identifiable {
        case red, blue, white, green, purple
        var id: String { rawValue }
        var name: String { rawValue.capitalized }
        var nsColor: NSColor {
            switch self {
            case .red: return .systemRed
            case .blue: return .systemBlue
            case .white: return .white
            case .green: return .systemGreen
            case .purple: return .systemPurple
            }
        }
    }

    @Published var visible: Bool { didSet { defaults.set(visible, forKey: "zoneVisible"); redraw() } }
    @Published var color: FrameColor { didSet { defaults.set(color.rawValue, forKey: "zoneColor"); redraw() } }
    /// Zone height in points, or `maxSize` for the largest 16:9 area that fits the screen.
    @Published var size: Int { didSet { defaults.set(size, forKey: "zoneSize"); recompute() } }
    /// Display holding the zone, or `autoScreen` for the widest one.
    @Published var screenID: CGDirectDisplayID { didSet { defaults.set(Int(screenID), forKey: "zoneScreen"); recompute() } }
    @Published var dimOutside: Bool { didSet { defaults.set(dimOutside, forKey: "zoneDim"); redraw() } }
    @Published var snapOnDrop: Bool { didSet { defaults.set(snapOnDrop, forKey: "zoneSnap"); updateSnapper() } }

    /// Zone and its screen in Cocoa coordinates (origin bottom-left of the primary screen).
    @Published private(set) var rect: CGRect = .zero
    @Published private(set) var screenFrame: CGRect = .zero
    @Published private(set) var scale: CGFloat = 1
    @Published private(set) var screens: [ScreenOption] = []
    @Published private(set) var screenName = ""

    private let defaults = UserDefaults.standard
    private let overlay = ZoneOverlay()
    private let snapper = DragSnapper()
    private var preview: CGRect?

    private init() {
        visible = defaults.object(forKey: "zoneVisible") as? Bool ?? true
        color = FrameColor(rawValue: defaults.string(forKey: "zoneColor") ?? "") ?? .red
        size = defaults.object(forKey: "zoneSize") as? Int ?? Self.maxSize
        screenID = CGDirectDisplayID(defaults.integer(forKey: "zoneScreen"))
        dimOutside = defaults.bool(forKey: "zoneDim")
        snapOnDrop = defaults.object(forKey: "zoneSnap") as? Bool ?? true

        snapper.slotAt = { [weak self] p in self?.slot(at: p) }
        snapper.onPreview = { [weak self] slot in
            guard let self else { return }
            preview = slot.map { self.frame(for: $0) }
            redraw()
        }
        snapper.onDrop = { [weak self] w, slot in self?.place(w, slot) }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.recompute() }
    }

    func start() {
        recompute()
        updateSnapper()
    }

    // MARK: Geometry

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// The chosen screen; falls back to the widest one (the ultrawide when there is one)
    /// while the chosen screen is disconnected.
    private var screen: NSScreen? {
        NSScreen.screens.first { Self.displayID(of: $0) == screenID }
            ?? NSScreen.screens.max { $0.frame.width < $1.frame.width }
    }

    /// Largest 16:9 area that fits the screen, in points.
    var maxFit: CGSize {
        let w = screenFrame.width, h = screenFrame.height
        return w * 9 / 16 <= h
            ? CGSize(width: w.rounded(.down), height: (w * 9 / 16).rounded(.down))
            : CGSize(width: (h * 16 / 9).rounded(.down), height: h.rounded(.down))
    }

    /// Size choices for this screen: the common heights that fit, then the max.
    var sizeOptions: [Int] {
        Self.heights.filter { CGFloat($0) < maxFit.height } + [Self.maxSize]
    }

    func label(for size: Int) -> String {
        size == Self.maxSize
            ? "Max · \(Int(maxFit.width))×\(Int(maxFit.height))"
            : "\(size * 16 / 9)×\(size)"
    }

    private func recompute() {
        screens = NSScreen.screens.map { ScreenOption(id: Self.displayID(of: $0), name: $0.localizedName) }
        guard let screen else { return }
        screenFrame = screen.frame
        screenName = screen.localizedName
        scale = screen.backingScaleFactor
        // A size saved on a bigger screen falls back to the max on this one.
        let zone = sizeOptions.contains(size) && size != Self.maxSize
            ? CGSize(width: CGFloat(size * 16 / 9), height: CGFloat(size))
            : maxFit
        rect = CGRect(x: (screenFrame.midX - zone.width / 2).rounded(),
                      y: (screenFrame.midY - zone.height / 2).rounded(),
                      width: zone.width, height: zone.height)
        redraw()
    }

    var pixelSize: CGSize { CGSize(width: rect.width * scale, height: rect.height * scale) }

    /// Values for OBS → Display Capture → Crop, in pixels.
    var crop: (left: Int, right: Int, top: Int, bottom: Int) {
        func px(_ v: CGFloat) -> Int { Int((v * scale).rounded()) }
        return (px(rect.minX - screenFrame.minX), px(screenFrame.maxX - rect.maxX),
                px(screenFrame.maxY - rect.maxY), px(rect.minY - screenFrame.minY))
    }

    /// Which part of the zone a drop at `p` (Cocoa) lands in: the outer fifths are the halves.
    func slot(at p: CGPoint) -> Slot? {
        guard rect.contains(p) else { return nil }
        let f = (p.x - rect.minX) / rect.width
        return f < 0.2 ? .left : f > 0.8 ? .right : .full
    }

    /// Where a window goes for a slot (Cocoa): the zone minus menu bar / Dock.
    func frame(for slot: Slot) -> CGRect {
        var r = rect
        if let visible = screen?.visibleFrame, rect.intersects(visible) { r = rect.intersection(visible) }
        let half = (r.width / 2).rounded()
        switch slot {
        case .full: return r
        case .left: return CGRect(x: r.minX, y: r.minY, width: half, height: r.height)
        case .right: return CGRect(x: r.maxX - half, y: r.minY, width: half, height: r.height)
        }
    }

    // MARK: Actions

    func sendFocused(_ slot: Slot) {
        guard WindowManager.isTrusted else { WindowManager.requestPermission(); return }
        guard let w = WindowManager.focusedWindow() else { NSSound.beep(); return }
        place(w, slot)
    }

    private func place(_ w: AXUIElement, _ slot: Slot) {
        let target = WindowManager.toAX(frame(for: slot))
        let result = WindowManager.place(w, in: target)
        log.notice("place \(String(describing: slot), privacy: .public) → \(String(describing: target), privacy: .public): \(String(describing: result), privacy: .public)")
        if case .failed = result { NSSound.beep() }
    }

    private func redraw() {
        overlay.update(screen: screenFrame, zone: rect, border: visible, color: color.nsColor,
                       dim: visible && dimOutside, preview: preview)
    }

    private func updateSnapper() {
        if snapOnDrop { snapper.start() } else { snapper.stop() }
    }
}

// MARK: - Overlay

/// Click-through window over the whole screen that draws the zone's frame.
final class ZoneOverlay {
    private var window: NSWindow?
    private let view = ZoneOverlayView()

    func update(screen: CGRect, zone: CGRect, border: Bool, color: NSColor, dim: Bool, preview: CGRect?) {
        guard (border || preview != nil), !screen.isEmpty else { window?.orderOut(nil); return }
        let win = window ?? makeWindow()
        if win.frame != screen { win.setFrame(screen, display: false) }
        let dx = -screen.minX, dy = -screen.minY
        view.zone = zone.offsetBy(dx: dx, dy: dy)
        view.preview = preview?.offsetBy(dx: dx, dy: dy)
        view.border = border
        view.color = color
        view.dim = dim
        view.needsDisplay = true
        win.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.sharingType = .none // keep it out of screen captures where macOS honors this
        w.isReleasedWhenClosed = false
        w.contentView = view
        window = w
        return w
    }
}

private final class ZoneOverlayView: NSView {
    var zone = CGRect.zero
    var preview: CGRect?
    var border = true
    var color = NSColor.systemRed
    var dim = false

    private static let lineWidth: CGFloat = 2.5
    private static let radius: CGFloat = 10

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill(using: .copy)

        if dim {
            NSColor.black.withAlphaComponent(0.45).setFill()
            let outside = NSBezierPath(rect: bounds)
            outside.append(NSBezierPath(rect: zone))
            outside.windingRule = .evenOdd
            outside.fill()
        }
        if border {
            // Pushed out far enough that the rounded corners stay outside the zone.
            let outset = Self.lineWidth / 2 + Self.radius * 0.3 + 1
            let frame = NSBezierPath(roundedRect: zone.insetBy(dx: -outset, dy: -outset),
                                     xRadius: Self.radius, yRadius: Self.radius)
            frame.lineWidth = Self.lineWidth
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = color.withAlphaComponent(0.6)
            glow.shadowBlurRadius = 8
            glow.set()
            color.withAlphaComponent(0.9).setStroke()
            frame.stroke()
            NSGraphicsContext.restoreGraphicsState()
            // Wipe anything that spilled inside: the zone itself is what goes on stream.
            NSColor.clear.set()
            zone.fill(using: .copy)
        }
        if let preview {
            let shape = NSBezierPath(roundedRect: preview.insetBy(dx: 4, dy: 4), xRadius: Self.radius, yRadius: Self.radius)
            color.withAlphaComponent(0.15).setFill()
            shape.fill()
            color.withAlphaComponent(0.8).setStroke()
            shape.lineWidth = 2
            shape.stroke()
        }
    }
}

// MARK: - Drag & drop snapping

/// Watches window drags system-wide and reports when one is dropped in the zone.
final class DragSnapper {
    var slotAt: ((CGPoint) -> StreamZone.Slot?)?
    var onPreview: ((StreamZone.Slot?) -> Void)?
    var onDrop: ((AXUIElement, StreamZone.Slot) -> Void)?

    private var monitors: [Any] = []
    private var window: AXUIElement?
    private var startOrigin: CGPoint?
    private var startSize: CGSize?
    private var moving = false
    private var slot: StreamZone.Slot?

    func start() {
        guard monitors.isEmpty else { return }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in self?.mouseDown() },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in self?.mouseDragged() },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.mouseUp() },
        ].compactMap { $0 }
        log.notice("snap monitors: \(self.monitors.count, privacy: .public)")
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        reset()
    }

    private func mouseDown() {
        reset()
        guard WindowManager.isTrusted else { log.notice("mouse down: no Accessibility permission"); return }
        guard let w = WindowManager.window(at: WindowManager.toAX(NSEvent.mouseLocation)) else {
            log.notice("mouse down: no window found under the cursor")
            return
        }
        window = w
        startOrigin = WindowManager.position(of: w)
        startSize = WindowManager.size(of: w)
    }

    private func mouseDragged() {
        guard let w = window else { return }
        if !moving {
            guard let origin = WindowManager.position(of: w), let size = WindowManager.size(of: w) else { return }
            // A resize changes the size: not ours to handle.
            if size != startSize { window = nil; return }
            moving = origin != startOrigin
            guard moving else { return }
            log.notice("window drag started")
        }
        let new = slotAt?(NSEvent.mouseLocation)
        if new != slot {
            slot = new
            onPreview?(new)
        }
    }

    private func mouseUp() {
        let drop = moving ? window.flatMap { w in slot.map { (w, $0) } } : nil
        if moving { log.notice("window dropped, slot: \(String(describing: self.slot), privacy: .public)") }
        reset()
        // Let the drag finish before moving the window.
        if let (w, slot) = drop { DispatchQueue.main.async { self.onDrop?(w, slot) } }
    }

    private func reset() {
        if slot != nil { onPreview?(nil) }
        window = nil
        startOrigin = nil
        startSize = nil
        moving = false
        slot = nil
    }
}
