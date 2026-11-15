import AppKit
import NotchyCore

/// Hidden verification flag: print, nudge +1/16, restore, exit. No UI, no server.
func runLevelsSelfTest() -> Never {
    let step: Float = 1.0 / 16
    if let v = VolumeControl.current() {
        print("volume: level=\(v.level) muted=\(v.muted) settable=\(VolumeControl.isSettable())")
        let target = VolumeLevel(level: min(1, v.level + step), muted: v.muted)
        let setOK = VolumeControl.set(target)
        let after = VolumeControl.current()
        let restoreOK = VolumeControl.set(v)
        let restored = VolumeControl.current()
        print("volume: set(+1/16)=\(setOK) readback=\(after.map { "\($0.level)" } ?? "nil") restore=\(restoreOK) now=\(restored.map { "level=\($0.level) muted=\($0.muted)" } ?? "nil")")
    } else {
        print("volume: unavailable")
    }
    print("brightness: available=\(BrightnessControl.isAvailable)")
    if let b = BrightnessControl.current() {
        print("brightness: level=\(b)")
        let setOK = BrightnessControl.set(min(1, b + step))
        let after = BrightnessControl.current()
        let restoreOK = BrightnessControl.set(b)
        let restored = BrightnessControl.current()
        print("brightness: set(+1/16)=\(setOK) readback=\(after.map { "\($0)" } ?? "nil") restore=\(restoreOK) now=\(restored.map { "\($0)" } ?? "nil")")
    }
    exit(0)
}

if CommandLine.arguments.contains("--selftest-levels") { runLevelsSelfTest() }

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
