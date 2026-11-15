import AppKit
import CoreGraphics
import NotchyCore

/// Session event tap for the volume/brightness media keys (NX_SYSDEFINED, subtype 8).
/// `onKey` decides per key-down whether Notchy handles (consumes) the key; a key-up is
/// consumed only if its key-down was. Anything else passes through to macOS untouched.
/// If the tap is disabled or never created, every key behaves natively.
///
/// The tap's run-loop source lives on the main run loop, so the C callback runs on main.
@MainActor
final class MediaKeyTap {
    /// NX_SYSDEFINED event type.
    private static let systemDefinedType: UInt32 = 14
    /// NX_SUBTYPE_AUX_CONTROL_BUTTONS.
    private static let mediaKeySubtype: Int16 = 8

    /// Called for key-downs (including auto-repeat) only; key-ups are paired here.
    /// Returns whether to consume the event.
    private let onKey: (MediaKey, _ fine: Bool) -> Bool
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    /// Whether the most recent key-down for each NX key code was consumed.
    private var consumedDown: [Int32: Bool] = [:]

    init(onKey: @escaping (MediaKey, _ fine: Bool) -> Bool) {
        self.onKey = onKey
    }

    var isRunning: Bool { port != nil }

    /// Creates and enables the tap. False if macOS refused it (e.g. no Accessibility).
    func start() -> Bool {
        if port != nil { return true }
        let mask = CGEventMask(1) << CGEventMask(Self.systemDefinedType)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: mediaKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            notchyLog.error("Media key tap: CGEvent.tapCreate failed")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        notchyLog.notice("Media key tap started")
        return true
    }

    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
        self.port = nil
        self.source = nil
        consumedDown.removeAll()
        notchyLog.notice("Media key tap stopped")
    }

    /// Runs on main inside the tap callback. Must stay cheap.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            notchyLog.notice("Media key tap re-enabled after \(type == .tapDisabledByTimeout ? "timeout" : "user input", privacy: .public)")
            return false
        }
        guard type.rawValue == Self.systemDefinedType,
              let ns = NSEvent(cgEvent: event),
              ns.subtype.rawValue == Self.mediaKeySubtype else { return false }
        let data1 = ns.data1
        let code = Int32((data1 & 0xFFFF_0000) >> 16)
        let isDown = ((data1 & 0xFF00) >> 8) == 0xA
        if !isDown {
            // Key-up (0xB) or anything else: consume only if the matching down was consumed.
            return consumedDown.removeValue(forKey: code) ?? false
        }
        guard let key = mediaKey(nxKeyType: code) else {
            consumedDown[code] = false
            return false
        }
        let flags = event.flags
        let option = flags.contains(.maskAlternate), shift = flags.contains(.maskShift)
        guard consumableModifiers(option: option, shift: shift,
                                  control: flags.contains(.maskControl),
                                  command: flags.contains(.maskCommand)) else {
            consumedDown[code] = false
            return false
        }
        let fine = option && shift
        let consume = onKey(key, fine)
        consumedDown[code] = consume
        return consume
    }
}

/// C callback: bridges to the MediaKeyTap passed as `userInfo`. Returning nil swallows the event.
private func mediaKeyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MediaKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
    // The run-loop source is on the main run loop, so this runs on the main thread.
    nonisolated(unsafe) let ev = event
    let consume = MainActor.assumeIsolated { tap.handle(type: type, event: ev) }
    return consume ? nil : Unmanaged.passUnretained(event)
}
