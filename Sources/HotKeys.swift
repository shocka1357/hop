import Carbon.HIToolbox

/// Thin wrapper around Carbon's RegisterEventHotKey.
/// System-wide hotkeys registered this way need no Accessibility permission.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private let signature: OSType = 0x486F_7021 // "Hop!"

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            HotKeyCenter.shared.fire(hotKeyID.id)
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Returns an id to unregister with, or nil if the combination is already taken.
    @discardableResult
    func register(keyCode: Int, modifiers: UInt32 = 0, handler: @escaping () -> Void) -> UInt32? {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), modifiers, EventHotKeyID(signature: signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        refs[id] = ref
        handlers[id] = handler
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers.removeValue(forKey: id)
    }

    private func fire(_ id: UInt32) {
        handlers[id]?()
    }
}
