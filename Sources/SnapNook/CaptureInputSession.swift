import AppKit
import ApplicationServices

/// Owns a blocking tap only for the lifetime of a screenshot selection.
final class CaptureInputSession {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let onEvent: (CGEventType, CGEvent) -> Void
    private let onFailure: () -> Void
    private var initiallyPressedKeys: Set<CGKeyCode>
    private var selectionPressedKeys: Set<CGKeyCode> = []
    private(set) var isStopped = false

    init(initiallyPressedKeys: Set<CGKeyCode> = Set((0..<128).filter {
        CGEventSource.keyState(.combinedSessionState, key: $0)
    }), onEvent: @escaping (CGEventType, CGEvent) -> Void, onFailure: @escaping () -> Void) {
        self.initiallyPressedKeys = initiallyPressedKeys
        self.onEvent = onEvent
        self.onFailure = onFailure
    }

    func start() -> Bool {
        guard tap == nil, !isStopped else { return false }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return false }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                    .rightMouseDown, .rightMouseDragged, .rightMouseUp,
                                    .otherMouseDown, .otherMouseDragged, .otherMouseUp,
                                    .scrollWheel, .keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .defaultTap, eventsOfInterest: mask,
                                         callback: { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let session = Unmanaged<CaptureInputSession>.fromOpaque(userInfo).takeUnretainedValue()
            return session.receive(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    @discardableResult
    func receive(type: CGEventType, event: CGEvent) -> Bool {
        guard !isStopped else { return false }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stop()
            onFailure()
            return false
        }
        onEvent(type, event)
        let key = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        switch type {
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                selectionPressedKeys.insert(key)
            }
        case .keyUp:
            // Carbon hotkeys can be absent from the system's pressed-key table.
            // Only consume releases whose press was consumed by this selection.
            initiallyPressedKeys.remove(key)
            return selectionPressedKeys.remove(key) != nil
        case .flagsChanged:
            if initiallyPressedKeys.remove(key) != nil { return false }
        default:
            break
        }
        return true
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
    }

    deinit { stop() }
}
