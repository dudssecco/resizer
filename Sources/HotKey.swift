import Carbon.HIToolbox

/// Global shortcuts (need no extra permission).
enum HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var refs: [EventHotKeyRef?] = []
    private static var installed = false

    /// `modifiers` uses Carbon flags (shiftKey, optionKey, controlKey, cmdKey).
    static func register(_ keyCode: Int, _ modifiers: Int, _ handler: @escaping () -> Void) {
        installHandler()
        let n = UInt32(handlers.count + 1)
        handlers[n] = handler
        let id = EventHotKeyID(signature: OSType(0x5253_5A52), id: n) // "RSZR"
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers),
                            id, GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }

    private static func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async { HotKey.handlers[id.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
