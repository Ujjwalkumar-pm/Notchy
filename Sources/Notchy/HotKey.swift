import AppKit
import Carbon.HIToolbox

/// Global hot key via Carbon `RegisterEventHotKey` (no Accessibility needed). Default ⌥⌘N.
@MainActor
final class HotKey {
    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let hotKeyID: UInt32
    private static let signature: OSType = 0x4E544359 // 'NTCY'

    private static var nextID: UInt32 = 1

    init(keyCode: UInt32 = UInt32(kVK_ANSI_N), modifiers: UInt32 = UInt32(optionKey | cmdKey)) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        hotKeyID = Self.nextID
        Self.nextID += 1
    }

    /// Returns false if macOS refused (e.g. another app holds the same combination).
    @discardableResult
    func register() -> Bool {
        guard ref == nil else { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            let mine = MainActor.assumeIsolated { id.signature == HotKey.signature && id.id == hotKey.hotKeyID }
            guard mine else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { hotKey.onPress?() }
            return noErr
        }, 1, &spec, me, &handler)
        guard status == noErr else { return false }
        let id = EventHotKeyID(signature: Self.signature, id: hotKeyID)
        let r = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if r != noErr {
            ref = nil
            if let handler { RemoveEventHandler(handler) }
            handler = nil
            return false
        }
        return true
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
