import AppKit
import ApplicationServices

/// A window belonging to another app, read through the Accessibility API.
struct WindowItem: Identifiable {
    let id = UUID()
    let element: AXUIElement
    let pid: pid_t
    let appName: String
    let title: String
    let icon: NSImage?
    let size: CGSize
    let isFullScreen: Bool
}

enum ResizeResult {
    case ok
    case limited(CGSize)   // the app didn't accept the exact size
    case failed(String)
}

enum WindowManager {

    // MARK: Permission

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Reading

    static func listWindows() -> [WindowItem] {
        var result: [WindowItem] = []
        let myPid = ProcessInfo.processInfo.processIdentifier

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != myPid {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.5)
            guard let windows: [AXUIElement] = attr(axApp, kAXWindowsAttribute) else { continue }

            for w in windows {
                // Skip popups, panels, tooltips, etc.
                let subrole: String? = attr(w, kAXSubroleAttribute)
                guard subrole == (kAXStandardWindowSubrole as String) else { continue }
                if let minimized: Bool = attr(w, kAXMinimizedAttribute), minimized { continue }

                let title: String = attr(w, kAXTitleAttribute) ?? ""
                let fullScreen: Bool = attr(w, "AXFullScreen") ?? false
                result.append(WindowItem(
                    element: w,
                    pid: app.processIdentifier,
                    appName: app.localizedName ?? "App",
                    title: title.isEmpty ? "(untitled)" : title,
                    icon: app.icon,
                    size: size(of: w) ?? .zero,
                    isFullScreen: fullScreen
                ))
            }
        }
        return result.sorted { ($0.appName, $0.title) < ($1.appName, $1.title) }
    }

    /// Focused window of the frontmost app (used by the global shortcut).
    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        return attr(axApp, kAXFocusedWindowAttribute)
    }

    // MARK: Resizing

    static func resize(_ w: AXUIElement, to target: CGSize, center: Bool) -> ResizeResult {
        if let fs: Bool = attr(w, "AXFullScreen"), fs {
            return .failed("is in full screen")
        }

        let err = setSize(w, target)
        if err != .success {
            return .failed("the app refused (error \(err.rawValue))")
        }

        if center, let pos = position(of: w), let cur = size(of: w) {
            let screen = visibleScreenRect(containing: CGRect(origin: pos, size: cur))
            let newOrigin = CGPoint(
                x: screen.midX - cur.width / 2,
                y: max(screen.minY, screen.midY - cur.height / 2)
            )
            setPosition(w, newOrigin)
            // Some apps only accept the final size after the window is moved.
            _ = setSize(w, target)
        }

        if let final = size(of: w),
           abs(final.width - target.width) > 1 || abs(final.height - target.height) > 1 {
            return .limited(final)
        }
        return .ok
    }

    // MARK: Helpers AX

    private static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func size(of w: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        AXValueGetValue(value as! AXValue, .cgSize, &s)
        return s
    }

    static func position(of w: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &p)
        return p
    }

    @discardableResult
    private static func setSize(_ w: AXUIElement, _ s: CGSize) -> AXError {
        var s = s
        guard let v = AXValueCreate(.cgSize, &s) else { return .failure }
        return AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, v)
    }

    @discardableResult
    private static func setPosition(_ w: AXUIElement, _ p: CGPoint) -> AXError {
        var p = p
        guard let v = AXValueCreate(.cgPoint, &p) else { return .failure }
        return AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, v)
    }

    /// Usable area (minus menu bar / Dock) of the screen holding the window,
    /// in AX coordinates (origin at the top-left of the primary screen).
    private static func visibleScreenRect(containing rect: CGRect) -> CGRect {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return .zero }
        let primaryH = primary.frame.height
        func toAX(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX, y: primaryH - r.maxY, width: r.width, height: r.height)
        }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let screen = screens.first { toAX($0.frame).contains(center) } ?? NSScreen.main ?? primary
        return toAX(screen.visibleFrame)
    }
}
