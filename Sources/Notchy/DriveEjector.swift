import DiskArbitration
import Foundation
import IOKit

/// Ejects the drive behind a volume, the way Finder does:
/// 1. whole-unmount the volume's whole disk (the synthesized container for APFS, else the
///    physical disk);
/// 2. if the physical disk differs (APFS store), whole-unmount it too;
/// 3. confirm the volume is really unmounted;
/// 4. `DADiskEject` the physical disk.
/// Self-contained (no app state) so it can be exercised by a standalone harness.
@MainActor
enum DriveEjector {
    enum Outcome: Equatable {
        case ejected
        /// A step was refused; `status` is the DiskArbitration status (e.g. kDAReturnBusy).
        case failed(step: String, status: Int32)
    }

    static func eject(volumeBSD: String, session: DASession, done: @escaping @MainActor (Outcome) -> Void) {
        guard let volume = DADiskCreateFromBSDName(kCFAllocatorDefault, session, volumeBSD),
              let container = DADiskCopyWholeDisk(volume) else {
            done(.failed(step: "lookup", status: -1))
            return
        }
        let physical = physicalWholeDisk(of: container, session: session) ?? container
        let differs = bsd(physical) != bsd(container)

        unmountWhole(container) { status in
            if let status { done(.failed(step: "unmount", status: status)); return }
            let afterUnmount: @MainActor () -> Void = {
                // The volume must really be gone before ejecting (else eject reports busy).
                if isMounted(volume) {
                    done(.failed(step: "verify", status: Int32(bitPattern: UInt32(kDAReturnBusy))))
                    return
                }
                ejectDisk(physical) { status in
                    if let status { done(.failed(step: "eject", status: status)) } else { done(.ejected) }
                }
            }
            guard differs else { afterUnmount(); return }
            unmountWhole(physical) { status in
                if let status { done(.failed(step: "unmount-store", status: status)); return }
                afterUnmount()
            }
        }
    }

    private static func bsd(_ d: DADisk) -> String? {
        DADiskGetBSDName(d).map { String(cString: $0) }
    }

    private static func isMounted(_ d: DADisk) -> Bool {
        guard let desc = DADiskCopyDescription(d) as? [String: Any] else { return false }
        return desc[kDADiskDescriptionVolumePathKey as String] != nil
    }

    /// Carries a completion through a C callback. `nil` status = success.
    private final class Box {
        let f: @MainActor (Int32?) -> Void
        init(_ f: @escaping @MainActor (Int32?) -> Void) { self.f = f }
    }

    private static func unmountWhole(_ d: DADisk, then f: @escaping @MainActor (Int32?) -> Void) {
        let ctx = Unmanaged.passRetained(Box(f)).toOpaque()
        DADiskUnmount(d, DADiskUnmountOptions(kDADiskUnmountOptionWhole), { _, dissenter, ctx in
            guard let ctx else { return }
            let status: Int32? = dissenter.map { DADissenterGetStatus($0) }
            nonisolated(unsafe) let c = ctx
            MainActor.assumeIsolated { Unmanaged<Box>.fromOpaque(c).takeRetainedValue().f(status) }
        }, ctx)
    }

    private static func ejectDisk(_ d: DADisk, then f: @escaping @MainActor (Int32?) -> Void) {
        let ctx = Unmanaged.passRetained(Box(f)).toOpaque()
        DADiskEject(d, DADiskEjectOptions(kDADiskEjectOptionDefault), { _, dissenter, ctx in
            guard let ctx else { return }
            let status: Int32? = dissenter.map { DADissenterGetStatus($0) }
            nonisolated(unsafe) let c = ctx
            MainActor.assumeIsolated { Unmanaged<Box>.fromOpaque(c).takeRetainedValue().f(status) }
        }, ctx)
    }

    /// The physical whole disk behind a whole disk: walks IOMedia parents past an APFS
    /// container (IOMedia diskN synthesized ← AppleAPFSContainer ← IOMedia diskMsK ← … ← diskM).
    /// Returns nil when there is nothing further up (already physical).
    static func physicalWholeDisk(of whole: DADisk, session: DASession) -> DADisk? {
        let media = DADiskCopyIOMedia(whole)
        guard media != 0 else { return nil }
        var entry = media
        var found: DADisk?
        for _ in 0..<12 {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS else { break }
            IOObjectRelease(entry)
            entry = parent
            func prop(_ k: String) -> Any? {
                IORegistryEntryCreateCFProperty(entry, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            if IOObjectConformsTo(entry, "IOMedia") != 0, (prop("Whole") as? Bool) == true,
               let name = prop("BSD Name") as? String {
                found = DADiskCreateFromBSDName(kCFAllocatorDefault, session, name)
                break
            }
        }
        IOObjectRelease(entry)
        return found
    }
}
