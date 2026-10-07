import Carbon

/// Temporary session shortcut works even after the underlying app becomes key.
final class ScrollingEscapeShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onEscape: () -> Void

    init(onEscape: @escaping () -> Void) {
        self.onEscape = onEscape
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard identifier.signature == 0x534E5343 else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<ScrollingEscapeShortcut>.fromOpaque(context).takeUnretainedValue()
            shortcut.onEscape()
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: 0x534E5343, id: 1),
                            GetApplicationEventTarget(), 0, &hotKey)
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
