import AppKit
import DiskArbitration
import IOBluetooth
import IOKit
import IOKit.ps
import IOKit.usb
import NotchyCore

/// Watches Bluetooth, external drives, USB devices and power, event-driven only (no polling).
/// Devices present when it starts are never reported — only changes after that.
/// Logs carry kinds/counts only, never device names or serials.
@MainActor
final class DeviceMonitor: NSObject {
    /// Called for each event; `eject` is set for mounted drives (runs the Eject pill).
    var onEvent: ((DeviceEvent, (@MainActor () -> Void)?) -> Void)?
    private(set) var isRunning = false
    /// Bumped on every start/stop; delayed one-shots and eject callbacks from an older run no-op.
    private var generation = 0

    // Bluetooth
    private var btConnectNote: IOBluetoothUserNotification?
    private var btDisconnectNotes: [String: IOBluetoothUserNotification] = [:]
    /// Devices connected at start: their initial connect notification is swallowed.
    private var btAtStart: Set<String> = []

    // Drives
    private var daSession: DASession?
    /// BSD names of volumes mounted at start (not reported until they change).
    private var drivesAtStart: Set<String> = []
    /// Volume BSD name → name, for volumes we saw mounted (needed after they unmount).
    private var mountedDrives: [String: String] = [:]
    /// Unmounted cleanly before disappearing (→ "Ejected — safe to remove").
    private var cleanlyUnmounted: Set<String> = []
    /// Being ejected by Notchy: the eject callback reports it, disappearing says nothing.
    private var ejectingByUs: Set<String> = []

    // USB
    private var usbPort: IONotificationPortRef?
    private var usbAddedIter: io_iterator_t = 0
    private var usbRemovedIter: io_iterator_t = 0
    /// Registry entry id → name of reportable USB devices (incl. ones present at start).
    private var usbNames: [UInt64: String] = [:]

    // Power
    private var powerSource: CFRunLoopSource?
    private var lastOnAC: Bool?
    private var lowGate = LowBatteryGate()

    // MARK: - Start / stop

    func start() {
#if NOTCHY_CAPTURE
        return
#endif
        guard !isRunning else { return }
        isRunning = true
        generation += 1
        startPower()
        startDrives()
        startUSB()
        startBluetooth()
        notchyLog.notice("devices: watching (bt at start \(self.btAtStart.count), drives \(self.drivesAtStart.count), usb \(self.usbNames.count))")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation += 1
        btConnectNote?.unregister()
        btConnectNote = nil
        btDisconnectNotes.values.forEach { $0.unregister() }
        btDisconnectNotes.removeAll()
        btAtStart.removeAll()

        if let s = daSession {
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            DAUnregisterCallback(s, unsafeBitCast(daDiskAppeared as DADiskAppearedCallback, to: UnsafeMutableRawPointer.self), ctx)
            DAUnregisterCallback(s, unsafeBitCast(daDiskDisappeared as DADiskDisappearedCallback, to: UnsafeMutableRawPointer.self), ctx)
            DAUnregisterCallback(s, unsafeBitCast(daDiskChanged as DADiskDescriptionChangedCallback, to: UnsafeMutableRawPointer.self), ctx)
            DASessionUnscheduleFromRunLoop(s, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
        daSession = nil
        drivesAtStart.removeAll()
        mountedDrives.removeAll()
        cleanlyUnmounted.removeAll()
        ejectingByUs.removeAll()

        if usbAddedIter != 0 { IOObjectRelease(usbAddedIter); usbAddedIter = 0 }
        if usbRemovedIter != 0 { IOObjectRelease(usbRemovedIter); usbRemovedIter = 0 }
        if let p = usbPort { IONotificationPortDestroy(p) }
        usbPort = nil
        usbNames.removeAll()

        if let src = powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        powerSource = nil
        lastOnAC = nil
        notchyLog.notice("devices: stopped")
    }

    private func emit(_ e: DeviceEvent, eject: (@MainActor () -> Void)? = nil) {
        guard isRunning else { return }
        notchyLog.notice("devices: event \(e.logKind, privacy: .public)")
        onEvent?(e, eject)
    }

    // MARK: - Power

    private func startPower() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            MainActor.assumeIsolated {
                Unmanaged<DeviceMonitor>.fromOpaque(ctx).takeUnretainedValue().powerChanged()
            }
        }, ctx)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        powerSource = src
        // Seed silently: the state at launch is not an event.
        if let s = Self.readBattery() {
            lastOnAC = s.onAC
            _ = lowGate.update(percent: s.percent, charging: s.onAC)
        }
    }

    private struct BatteryState { var onAC: Bool; var percent: Int; var minutes: Int? }

    private static func readBattery() -> BatteryState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let pct = max > 0 ? Int((Double(cur) * 100 / Double(max)).rounded()) : cur
            let key = onAC ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let m = d[key] as? Int
            return BatteryState(onAC: onAC, percent: pct, minutes: (m ?? -1) > 0 ? m : nil)
        }
        return nil
    }

    private func powerChanged() {
        guard isRunning, let s = Self.readBattery() else { return }
        if let last = lastOnAC, last != s.onAC {
            emit(.power(charging: s.onAC, percent: s.percent, minutesToFullOrEmpty: s.minutes))
        }
        lastOnAC = s.onAC
        if lowGate.update(percent: s.percent, charging: s.onAC) {
            emit(.lowBattery(percent: s.percent))
        }
    }

    // MARK: - Drives (DiskArbitration)

    private func startDrives() {
        guard let s = DASessionCreate(kCFAllocatorDefault) else { return }
        // Volumes already mounted are not news. getmntinfo(MNT_NOWAIT) never blocks on a hung
        // network mount; only /dev/ devices are kept.
        var mounts: UnsafeMutablePointer<statfs>?
        let n = Int(getmntinfo(&mounts, MNT_NOWAIT))
        for i in 0..<n {
            guard var fs = mounts?[i] else { continue }
            let from = withUnsafePointer(to: &fs.f_mntfromname) {
                String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
            }
            if from.hasPrefix("/dev/") { drivesAtStart.insert(String(from.dropFirst(5))) }
        }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskAppearedCallback(s, nil, daDiskAppeared, ctx)
        DARegisterDiskDisappearedCallback(s, nil, daDiskDisappeared, ctx)
        let keys = [kDADiskDescriptionVolumePathKey] as CFArray
        DARegisterDiskDescriptionChangedCallback(s, nil, keys, daDiskChanged, ctx)
        DASessionScheduleWithRunLoop(s, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        daSession = s
    }

    /// External/removable, mountable, real (not a disk image, network or system volume).
    private static func isReportable(_ d: [String: Any]) -> Bool {
        if d[kDADiskDescriptionVolumeNetworkKey as String] as? Bool == true { return false }
        if d[kDADiskDescriptionVolumeMountableKey as String] as? Bool == false { return false }
        let model = (d[kDADiskDescriptionDeviceModelKey as String] as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
        let proto = d[kDADiskDescriptionDeviceProtocolKey as String] as? String ?? ""
        if model == "Disk Image" || proto == "Disk Image" || proto == "Virtual Interface" { return false }
        let isInternal = d[kDADiskDescriptionDeviceInternalKey as String] as? Bool ?? true
        let removable = d[kDADiskDescriptionMediaRemovableKey as String] as? Bool ?? false
        let ejectable = d[kDADiskDescriptionMediaEjectableKey as String] as? Bool ?? false
        if isInternal && !removable && !ejectable { return false }
        if let path = (d[kDADiskDescriptionVolumePathKey as String] as? URL)?.path,
           path == "/" || path.hasPrefix("/System/") { return false }
        return true
    }

    fileprivate func diskAppeared(_ disk: DADisk) {
        guard let bsd = bsdName(disk), !drivesAtStart.contains(bsd) else { return }
        volumeMaybeMounted(disk, bsd: bsd)
    }

    fileprivate func diskChanged(_ disk: DADisk) {
        guard let bsd = bsdName(disk) else { return }
        let d = description(disk)
        if d[kDADiskDescriptionVolumePathKey as String] is URL {
            if !drivesAtStart.contains(bsd) { volumeMaybeMounted(disk, bsd: bsd) }
        } else {
            // Unmounted (still attached).
            drivesAtStart.remove(bsd)
            if mountedDrives[bsd] != nil { cleanlyUnmounted.insert(bsd) }
        }
    }

    fileprivate func diskDisappeared(_ disk: DADisk) {
        guard let bsd = bsdName(disk) else { return }
        drivesAtStart.remove(bsd)
        guard let name = mountedDrives.removeValue(forKey: bsd) else { return }
        let clean = cleanlyUnmounted.remove(bsd) != nil
        if ejectingByUs.contains(bsd) { return }
        emit(.drive(name: name, mounted: false, freeBytes: nil, ejected: clean))
    }

    private func volumeMaybeMounted(_ disk: DADisk, bsd: String) {
        let d = description(disk)
        guard let url = d[kDADiskDescriptionVolumePathKey as String] as? URL,
              mountedDrives[bsd] == nil, Self.isReportable(d) else { return }
        let name = d[kDADiskDescriptionVolumeNameKey as String] as? String ?? url.lastPathComponent
        mountedDrives[bsd] = name
        cleanlyUnmounted.remove(bsd)
        let free = (try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity
        emit(.drive(name: name, mounted: true, freeBytes: free.map(Int64.init), ejected: false)) { [weak self] in
            self?.eject(bsd: bsd)
        }
    }

    private func bsdName(_ disk: DADisk) -> String? {
        DADiskGetBSDName(disk).map { String(cString: $0) }
    }

    private func description(_ disk: DADisk) -> [String: Any] {
        (DADiskCopyDescription(disk) as? [String: Any]) ?? [:]
    }

    /// Eject pill: unmount the drive's volumes, then eject the physical disk (see DriveEjector).
    func eject(bsd: String) {
        guard let s = daSession, let name = mountedDrives[bsd], !ejectingByUs.contains(bsd) else { return }
        ejectingByUs.insert(bsd)
        let gen = generation
        DriveEjector.eject(volumeBSD: bsd, session: s) { [weak self] outcome in
            guard let self, self.isRunning, self.generation == gen else { return }
            self.ejectingByUs.remove(bsd)
            switch outcome {
            case .ejected:
                self.mountedDrives[bsd] = nil
                self.cleanlyUnmounted.remove(bsd)
                self.emit(.drive(name: name, mounted: false, freeBytes: nil, ejected: true))
            case let .failed(step, status):
                notchyLog.error("devices: eject refused at \(step, privacy: .public) (status 0x\(String(UInt32(bitPattern: status), radix: 16), privacy: .public))")
                self.emit(.ejectFailed(name: name))
            }
        }
    }

    // MARK: - USB (non-storage devices; name only)

    private func startUSB() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        usbPort = port
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("IOUSBHostDevice"),
                                         { ctx, iter in
            guard let ctx else { return }
            MainActor.assumeIsolated {
                Unmanaged<DeviceMonitor>.fromOpaque(ctx).takeUnretainedValue().usbAdded(iter, report: true)
            }
        }, ctx, &usbAddedIter)
        IOServiceAddMatchingNotification(port, kIOTerminatedNotification, IOServiceMatching("IOUSBHostDevice"),
                                         { ctx, iter in
            guard let ctx else { return }
            MainActor.assumeIsolated {
                Unmanaged<DeviceMonitor>.fromOpaque(ctx).takeUnretainedValue().usbRemoved(iter)
            }
        }, ctx, &usbRemovedIter)
        // Draining arms the notifications; devices already present are recorded, not reported.
        usbAdded(usbAddedIter, report: false)
        usbRemoved(usbRemovedIter)
    }

    private func usbAdded(_ iter: io_iterator_t, report: Bool) {
        while case let svc = IOIteratorNext(iter), svc != 0 {
            defer { IOObjectRelease(svc) }
            guard let name = Self.usbName(svc) else { continue }
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(svc, &id)
            guard report else {
                if !Self.hasMassStorageInterface(svc) { usbNames[id] = name }
                continue
            }
            // Interfaces attach just after the device: check for mass storage once, shortly
            // after (storage shows as a drive banner instead). One-shot, bounded.
            let gen = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.generation == gen else { return }
                    self.usbSettled(id: id, name: name)
                }
            }
        }
    }

    private func usbSettled(id: UInt64, name: String) {
        guard isRunning else { return }
        guard let match = IORegistryEntryIDMatching(id) else { return }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, match)
        guard svc != 0 else { return } // already gone
        defer { IOObjectRelease(svc) }
        if Self.hasMassStorageInterface(svc) { return }
        usbNames[id] = name
        emit(.usb(name: name, connected: true))
    }

    private func usbRemoved(_ iter: io_iterator_t) {
        while case let svc = IOIteratorNext(iter), svc != 0 {
            defer { IOObjectRelease(svc) }
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(svc, &id)
            if let name = usbNames.removeValue(forKey: id) {
                emit(.usb(name: name, connected: false))
            }
        }
    }

    /// Name of a reportable USB device; nil for hubs, built-in/internal and nameless devices.
    /// Apple's vendor id is deliberately not skipped: external Apple devices get banners.
    private static func usbName(_ svc: io_service_t) -> String? {
        func prop(_ k: String) -> Any? {
            IORegistryEntryCreateCFProperty(svc, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        if (prop("bDeviceClass") as? Int) == 9 { return nil } // hub
        if (prop("Built-In") as? Bool) == true || (prop("non-removable") as? String) == "yes" { return nil }
        let name = (prop("USB Product Name") as? String) ?? (prop("kUSBProductString") as? String)
        guard let name, !name.isEmpty, !name.localizedCaseInsensitiveContains("hub") else { return nil }
        return name
    }

    private static func hasMassStorageInterface(_ svc: io_service_t) -> Bool {
        var iter: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(svc, kIOServicePlane, &iter) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iter) }
        while case let child = IOIteratorNext(iter), child != 0 {
            defer { IOObjectRelease(child) }
            if let c = IORegistryEntryCreateCFProperty(child, "bInterfaceClass" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int, c == 8 { return true }
        }
        return false
    }

    // MARK: - Bluetooth

    private func startBluetooth() {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        for dev in paired where dev.isConnected() {
            let addr = dev.addressString ?? ""
            btAtStart.insert(addr)
            watchDisconnect(dev)
        }
        btConnectNote = IOBluetoothDevice.register(forConnectNotifications: self,
                                                   selector: #selector(btConnected(_:device:)))
    }

    private func watchDisconnect(_ dev: IOBluetoothDevice) {
        let addr = dev.addressString ?? ""
        guard btDisconnectNotes[addr] == nil else { return }
        btDisconnectNotes[addr] = dev.register(forDisconnectNotification: self,
                                               selector: #selector(btDisconnected(_:device:)))
    }

    @objc private func btConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard isRunning else { return }
        let addr = device.addressString ?? ""
        watchDisconnect(device)
        // Registration replays devices already connected: those are not news.
        if btAtStart.remove(addr) != nil { return }
        let name = device.name ?? "Bluetooth device"
        let levels = Self.batteryLevels(device)
        if levels.isEmpty {
            // Battery often arrives a moment after connecting: one bounded re-read.
            let gen = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.isRunning, self.generation == gen, device.isConnected() else { return }
                    self.emitBluetooth(name: name, connected: true, Self.batteryLevels(device))
                }
            }
        } else {
            emitBluetooth(name: name, connected: true, levels)
        }
    }

    @objc private func btDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        note.unregister()
        let addr = device.addressString ?? ""
        btDisconnectNotes[addr] = nil
        btAtStart.remove(addr)
        guard isRunning else { return }
        emitBluetooth(name: device.name ?? "Bluetooth device", connected: false, BatteryLevels())
    }

    private func emitBluetooth(name: String, connected: Bool, _ l: BatteryLevels) {
        emit(.bluetooth(name: name, connected: connected, battery: l.single, left: l.left,
                        right: l.right, case: l.caseLevel))
    }

    private struct BatteryLevels {
        var single: Int?, left: Int?, right: Int?, caseLevel: Int?
        var isEmpty: Bool { single == nil && left == nil && right == nil && caseLevel == nil }
    }

    /// IORegistry first (`BatteryPercent*` on the HID event service with this address or
    /// product name); else the levels IOBluetooth reports for AirPods-style devices.
    private static func batteryLevels(_ dev: IOBluetoothDevice) -> BatteryLevels {
        var l = registryBattery(address: dev.addressString ?? "", name: dev.name ?? "")
        guard l.isEmpty else { return l }
        func kv(_ k: String) -> Int? {
            guard dev.responds(to: NSSelectorFromString(k)),
                  let n = dev.value(forKey: k) as? NSNumber else { return nil }
            let v = n.intValue
            return (1...100).contains(v) ? v : nil
        }
        l.single = kv("batteryPercentSingle")
        l.left = kv("batteryPercentLeft")
        l.right = kv("batteryPercentRight")
        l.caseLevel = kv("batteryPercentCase")
        return l
    }

    private static func registryBattery(address: String, name: String) -> BatteryLevels {
        var out = BatteryLevels()
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                           &iter) == KERN_SUCCESS else { return out }
        defer { IOObjectRelease(iter) }
        let want = address.lowercased().replacingOccurrences(of: ":", with: "-")
        while case let svc = IOIteratorNext(iter), svc != 0 {
            defer { IOObjectRelease(svc) }
            func prop(_ k: String) -> Any? {
                IORegistryEntryCreateCFProperty(svc, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            let addr = (prop("DeviceAddress") as? String)?.lowercased().replacingOccurrences(of: ":", with: "-")
            let product = prop("Product") as? String
            guard (addr != nil && addr == want) || (addr == nil && product == name) else { continue }
            func pct(_ k: String) -> Int? {
                guard let v = prop(k) as? Int, (0...100).contains(v) else { return nil }
                return v
            }
            out.single = pct("BatteryPercent")
            out.left = pct("BatteryPercentLeft")
            out.right = pct("BatteryPercentRight")
            out.caseLevel = pct("BatteryPercentCase")
            if !out.isEmpty { break }
        }
        return out
    }
}

// DiskArbitration callbacks (scheduled on the main run loop).
private func daDiskAppeared(_ disk: DADisk, _ ctx: UnsafeMutableRawPointer?) {
    guard let ctx else { return }
    nonisolated(unsafe) let ctx0 = ctx, disk0 = disk
    MainActor.assumeIsolated { Unmanaged<DeviceMonitor>.fromOpaque(ctx0).takeUnretainedValue().diskAppeared(disk0) }
}

private func daDiskDisappeared(_ disk: DADisk, _ ctx: UnsafeMutableRawPointer?) {
    guard let ctx else { return }
    nonisolated(unsafe) let ctx0 = ctx, disk0 = disk
    MainActor.assumeIsolated { Unmanaged<DeviceMonitor>.fromOpaque(ctx0).takeUnretainedValue().diskDisappeared(disk0) }
}

private func daDiskChanged(_ disk: DADisk, _ keys: CFArray, _ ctx: UnsafeMutableRawPointer?) {
    guard let ctx else { return }
    nonisolated(unsafe) let ctx0 = ctx, disk0 = disk
    MainActor.assumeIsolated { Unmanaged<DeviceMonitor>.fromOpaque(ctx0).takeUnretainedValue().diskChanged(disk0) }
}
