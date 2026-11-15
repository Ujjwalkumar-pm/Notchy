import AppKit
import ApplicationServices
import CoreAudio
import CoreMediaIO
import Intents
import NotchyCore

/// Watches what the quiet rules need, event-driven only (no timers that repeat), and only the
/// parts whose switch is on (`apply`):
/// - in a call: a process other than dictation/Siri/Notchy running audio input (CoreAudio
///   process objects, macOS 14+; falls back to the default input device), or any camera
///   running somewhere (CoreMediaIO);
/// - full screen: the frontmost app's focused window `AXFullScreen` (needs Accessibility), re-read
///   on app activation, Space change and the front app's AX window notifications;
/// - Focus: `INFocusStatusCenter` (read on demand; it has no change notification for apps).
/// Screen-share detection is not done (it needs Screen Recording permission).
@MainActor
final class QuietMonitor: ObservableObject {
    @Published private(set) var micRunning = false
    @Published private(set) var cameraRunning = false
    @Published private(set) var fullScreenFront = false
    /// nil = unknown / not available.
    @Published private(set) var focusOn: Bool?
    @Published private(set) var focusAuthorization: INFocusStatusAuthorizationStatus = .notDetermined

    var inCall: Bool { micRunning || cameraRunning }

    private var callsOn = false
    private var fullScreenOn = false
    private var focusOn_ = false
    private var workspaceObservers: [NSObjectProtocol] = []

    // CoreAudio: process objects (preferred)
    private var processListListener: AudioObjectPropertyListenerBlock?
    private var processListener: AudioObjectPropertyListenerBlock?
    private var processObjects: [AudioObjectID] = []
    /// Last set of input-running bundle ids logged (ids only, logged on change).
    private var loggedInputIDs: [String] = []
    // CoreAudio: default input device (fallback)
    private var inputDevice = AudioObjectID(kAudioObjectUnknown)
    private var defaultInputListener: AudioObjectPropertyListenerBlock?
    private var micListener: AudioObjectPropertyListenerBlock?

    // CoreMediaIO
    private var cameraDevices: [CMIOObjectID] = []
    private var cameraListener: CMIOObjectPropertyListenerBlock?
    private var cameraListListener: CMIOObjectPropertyListenerBlock?

    // AX (front app)
    private var axObserver: AXObserver?
    private var axApp: AXUIElement?
    private var axPid: pid_t = 0
    /// One-shot re-read after a Space change (the full-screen animation finishes later).
    private var settleWork: DispatchWorkItem?

    /// Focus authorization is requested at most once per run.
    private var askedFocus = false

    /// Starts/stops each watcher to match its switch: calls (mic + camera) while "Quiet while
    /// presenting" is on; full screen while that or "Hide in full screen" is on; Focus while
    /// "Respect Focus" is on. Turned-off parts are cleared.
    func apply(calls: Bool, fullScreen: Bool, focus: Bool) {
#if NOTCHY_CAPTURE
        return
#endif
        // System-wide AX timeout too (default ~6 s), even if the Alerts watcher never started.
        if fullScreen { AXTimeouts.applyGlobal() }
        if calls != callsOn {
            callsOn = calls
            if calls {
                attachMicWatch()
                attachCameras()
            } else {
                detachMicWatch()
                detachCameras()
                micRunning = false
                cameraRunning = false
            }
        }
        if fullScreen != fullScreenOn {
            fullScreenOn = fullScreen
            if fullScreen {
                let nc = NSWorkspace.shared.notificationCenter
                workspaceObservers.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                         object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.frontAppChanged() }
                })
                workspaceObservers.append(nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                         object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.spaceChanged() }
                })
                frontAppChanged()
            } else {
                for o in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
                workspaceObservers = []
                detachAX()
                settleWork?.cancel()
                settleWork = nil
                fullScreenFront = false
            }
        }
        if focus != focusOn_ {
            focusOn_ = focus
            if focus {
                requestFocusAccessIfNeeded()
                refreshFocus()
            } else {
                focusOn = nil
            }
        }
        notchyLog.notice("Quiet: watching calls \(calls), full screen \(fullScreen), Focus \(focus)")
    }

    func stop() { apply(calls: false, fullScreen: false, focus: false) }

    // MARK: - Focus

    /// Asks once for Focus access (shows macOS's prompt the first time), then reads the state.
    private func requestFocusAccessIfNeeded() {
        let center = INFocusStatusCenter.default
        focusAuthorization = center.authorizationStatus
        guard !askedFocus, center.authorizationStatus == .notDetermined else { return }
        askedFocus = true
        center.requestAuthorization { status in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    notchyLog.notice("Quiet: Focus authorization \(status.rawValue)")
                    self.focusAuthorization = status
                    self.refreshFocus()
                }
            }
        }
    }

    /// Re-reads Focus (called when a banner is about to show and when the panel opens).
    func refreshFocus() {
#if NOTCHY_CAPTURE
        return
#endif
        guard focusOn_ else { return }
        let center = INFocusStatusCenter.default
        let auth = center.authorizationStatus
        if auth != focusAuthorization { focusAuthorization = auth }
        let on: Bool? = (auth == .denied || auth == .restricted) ? nil : center.focusStatus.isFocused
        if on != focusOn {
            focusOn = on
            notchyLog.notice("Quiet: Focus \(on.map { $0 ? "on" : "off" } ?? "unknown", privacy: .public) (auth \(auth.rawValue))")
        }
    }

    /// Settings row subtitle: nil when Focus can be read.
    var focusUnavailableText: String? {
        switch focusAuthorization {
        case .denied: return "Focus access is off in System Settings"
        case .restricted: return "Not available on this Mac"
        default: return nil
        }
    }

    // MARK: - Microphone (default input device)

    private static func systemAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// Prefers per-process input state; falls back to the default input device.
    private func attachMicWatch() {
        var addr = Self.systemAddress(kAudioHardwarePropertyProcessObjectList)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.processListChanged() } }
        }
        if readProcessObjects() != nil,
           AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block) == noErr {
            processListListener = block
            attachProcesses()
            notchyLog.notice("Quiet: mic watched per process")
        } else {
            attachDefaultInput()
            notchyLog.notice("Quiet: mic watched per device (process list unreadable)")
        }
    }

    private func detachMicWatch() {
        detachProcesses()
        if let block = processListListener {
            var addr = Self.systemAddress(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
            processListListener = nil
        }
        detachDefaultInput()
    }

    private func readProcessObjects() -> [AudioObjectID]? {
        var addr = Self.systemAddress(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return nil }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return nil }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private func processListChanged() {
        guard callsOn, processListListener != nil else { return }
        detachProcesses()
        attachProcesses()
    }

    private func attachProcesses() {
        let ids = readProcessObjects() ?? []
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.readProcesses() } }
        }
        var addr = Self.systemAddress(kAudioProcessPropertyIsRunningInput)
        for id in ids where AudioObjectAddPropertyListenerBlock(id, &addr, .main, block) == noErr {
            processObjects.append(id)
        }
        processListener = block
        readProcesses()
    }

    private func detachProcesses() {
        if let block = processListener {
            var addr = Self.systemAddress(kAudioProcessPropertyIsRunningInput)
            for id in processObjects { AudioObjectRemovePropertyListenerBlock(id, &addr, .main, block) }
        }
        processObjects = []
        processListener = nil
    }

    private func readProcesses() {
        guard callsOn else { return }
        var running: [String?] = []
        for id in processObjects {
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var addr = Self.systemAddress(kAudioProcessPropertyIsRunningInput)
            guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, value != 0 else { continue }
            running.append(Self.bundleID(of: id))
        }
        let ids = running.map { $0 ?? "(none)" }.sorted()
        if ids != loggedInputIDs {
            loggedInputIDs = ids
            // Bundle ids only (no titles or content).
            notchyLog.notice("Quiet: input running in [\(ids.joined(separator: ", "), privacy: .public)]")
        }
        setMic(micInCall(inputBundleIDs: running))
    }

    private static func bundleID(of process: AudioObjectID) -> String? {
        var addr = systemAddress(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &addr, 0, nil, &size, &value) == noErr,
              let s = value?.takeRetainedValue() else { return nil }
        return s as String
    }

    private func setMic(_ on: Bool) {
        if on != micRunning {
            micRunning = on
            notchyLog.notice("Quiet: microphone call \(on)")
        }
    }

    private func attachDefaultInput() {
        var addr = Self.systemAddress(kAudioHardwarePropertyDefaultInputDevice)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.defaultInputChanged() } }
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block) == noErr {
            defaultInputListener = block
        }
        attachMic()
    }

    private func detachDefaultInput() {
        detachMic()
        if let block = defaultInputListener {
            var addr = Self.systemAddress(kAudioHardwarePropertyDefaultInputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
            defaultInputListener = nil
        }
    }

    private func defaultInputChanged() {
        guard callsOn, defaultInputListener != nil else { return }
        detachMic()
        attachMic()
        notchyLog.notice("Quiet: default input changed (mic running \(self.micRunning))")
    }

    private func attachMic() {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = Self.systemAddress(kAudioHardwarePropertyDefaultInputDevice)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else {
            micRunning = false
            return
        }
        inputDevice = id
        var runAddr = Self.systemAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.readMic() } }
        }
        if AudioObjectAddPropertyListenerBlock(id, &runAddr, .main, block) == noErr { micListener = block }
        readMic()
    }

    private func detachMic() {
        if let block = micListener, inputDevice != kAudioObjectUnknown {
            var addr = Self.systemAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
            AudioObjectRemovePropertyListenerBlock(inputDevice, &addr, .main, block)
        }
        micListener = nil
        inputDevice = AudioObjectID(kAudioObjectUnknown)
    }

    private func readMic() {
        guard callsOn, inputDevice != kAudioObjectUnknown else { return }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = Self.systemAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
        let ok = AudioObjectGetPropertyData(inputDevice, &addr, 0, nil, &size, &value) == noErr
        setMic(ok && value != 0)
    }

    // MARK: - Cameras (CoreMediaIO)

    private static func cmioAddress(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: selector,
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private func attachCameras() {
        var listAddr = Self.cmioAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        let listBlock: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.callsOn else { return }
                    self.detachCameraDevices()
                    self.attachCameraDevices()
                }
            }
        }
        if CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &listAddr, .main, listBlock) == noErr {
            cameraListListener = listBlock
        }
        attachCameraDevices()
    }

    private func detachCameras() {
        detachCameraDevices()
        if let block = cameraListListener {
            var addr = Self.cmioAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
            CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &addr, .main, block)
            cameraListListener = nil
        }
    }

    private func attachCameraDevices() {
        var addr = Self.cmioAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        var size: UInt32 = 0
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else {
            readCameras()
            return
        }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &ids) == noErr else { return }
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.readCameras() } }
        }
        var runAddr = Self.cmioAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        for id in ids where CMIOObjectAddPropertyListenerBlock(id, &runAddr, .main, block) == noErr {
            cameraDevices.append(id)
        }
        cameraListener = block
        readCameras()
    }

    private func detachCameraDevices() {
        if let block = cameraListener {
            var addr = Self.cmioAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
            for id in cameraDevices { CMIOObjectRemovePropertyListenerBlock(id, &addr, .main, block) }
        }
        cameraDevices = []
        cameraListener = nil
    }

    private func readCameras() {
        guard callsOn else { return }
        var addr = Self.cmioAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        let on = cameraDevices.contains { id in
            var value: UInt32 = 0
            var used: UInt32 = 0
            return CMIOObjectGetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == noErr
                && value != 0
        }
        if on != cameraRunning {
            cameraRunning = on
            notchyLog.notice("Quiet: camera in use \(on)")
        }
    }

    // MARK: - Full screen (front app's focused window)

    private func frontAppChanged() {
        guard fullScreenOn else { return }
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        if pid != axPid || axObserver == nil {
            detachAX()
            attachAX(pid: pid)
        }
        readFullScreen()
    }

    private func spaceChanged() {
        guard fullScreenOn else { return }
        frontAppChanged()
        // The full-screen transition is still animating when the Space changes: read once more.
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.readFullScreen() }
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private static let axNotifications = [
        kAXFocusedWindowChangedNotification, kAXWindowResizedNotification, kAXWindowMovedNotification,
        kAXWindowMiniaturizedNotification, kAXMainWindowChangedNotification,
    ]

    private func attachAX(pid: pid_t) {
        axPid = pid
        guard pid > 0, pid != getpid(), AXIsProcessTrusted() else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let monitor = Unmanaged<QuietMonitor>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.readFullScreen() }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AXTimeouts.seconds)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.axNotifications {
            AXObserverAddNotification(observer, app, n as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        axObserver = observer
        axApp = app
    }

    private func detachAX() {
        if let observer = axObserver, let app = axApp {
            for n in Self.axNotifications { AXObserverRemoveNotification(observer, app, n as CFString) }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        axObserver = nil
        axApp = nil
        axPid = 0
    }

    private func readFullScreen() {
        guard fullScreenOn else { return }
        var on = false
        if axPid > 0, axPid != getpid(), AXIsProcessTrusted() {
            let app = axApp ?? AXUIElementCreateApplication(axPid)
            // Short timeouts: a hung front app must not stall the main thread (default ~6 s).
            AXUIElementSetMessagingTimeout(app, AXTimeouts.seconds)
            var win: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &win) == .success,
               let win, CFGetTypeID(win) == AXUIElementGetTypeID() {
                let window = win as! AXUIElement
                AXUIElementSetMessagingTimeout(window, AXTimeouts.seconds)
                var fs: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fs) == .success,
                   let n = fs as? NSNumber {
                    on = n.boolValue
                }
            }
        }
        if on != fullScreenFront {
            fullScreenFront = on
            notchyLog.notice("Quiet: front app full screen \(on)")
        }
    }
}

#if NOTCHY_CAPTURE
/// Capture build only: a demo Focus state (the real Focus status is never read).
extension QuietMonitor {
    func captureSetFocus(_ on: Bool?) { focusOn = on }
}
#endif
