import Carbon.HIToolbox

/// Global ⇧⌥R shortcut (needs no extra permission).
enum HotKey {
    static var handler: (() -> Void)?
    private static var ref: EventHotKeyRef?

    static func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.handler?() }
            return noErr
        }, 1, &spec, nil, nil)

        let id = EventHotKeyID(signature: OSType(0x5253_5A52), id: 1) // "RSZR"
        RegisterEventHotKey(UInt32(kVK_ANSI_R),
                            UInt32(shiftKey | optionKey),
                            id, GetApplicationEventTarget(), 0, &ref)
    }
}
