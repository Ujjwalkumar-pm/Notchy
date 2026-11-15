import CoreAudio
import AudioToolbox
import NotchyCore

/// System output volume + mute via CoreAudio on the default output device.
/// The device is re-read on every call because it can change at any time.
enum VolumeControl {
    private static func defaultDevice() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
        return (st == noErr && dev != kAudioObjectUnknown) ? dev : nil
    }

    private static func volumeAddr() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static func muteAddr() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    /// The device's mute flag, or nil if it has none / can't be read.
    private static func currentMute(_ dev: AudioDeviceID) -> Bool? {
        var ma = muteAddr()
        guard AudioObjectHasProperty(dev, &ma) else { return nil }
        var m: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &ma, 0, nil, &size, &m) == noErr ? m != 0 : nil
    }

    static func current() -> VolumeLevel? {
        guard let dev = defaultDevice() else { return nil }
        var va = volumeAddr()
        var level: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(dev, &va, 0, nil, &size, &level) == noErr else { return nil }
        var muted = false
        var ma = muteAddr()
        if AudioObjectHasProperty(dev, &ma) {
            var m: UInt32 = 0
            var msize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(dev, &ma, 0, nil, &msize, &m) == noErr { muted = m != 0 }
        }
        return VolumeLevel(level: level, muted: muted)
    }

    static func isSettable() -> Bool {
        guard let dev = defaultDevice() else { return false }
        var va = volumeAddr()
        guard AudioObjectHasProperty(dev, &va) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(dev, &va, &settable) == noErr && settable.boolValue
    }

    static func set(_ v: VolumeLevel) -> Bool {
        guard let dev = defaultDevice() else { return false }
        var va = volumeAddr()
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(dev, &va),
              AudioObjectIsPropertySettable(dev, &va, &settable) == noErr, settable.boolValue else { return false }
        // Mute first, and only if it changes: any failure here leaves the device untouched,
        // so the caller's pass-through to macOS is clean (no double step).
        var ma = muteAddr()
        // No mute property (or unreadable) counts as unmuted.
        let nowMuted = currentMute(dev) ?? false
        if nowMuted != v.muted {
            var msettable: DarwinBoolean = false
            // Covers: muted and can't unmute (would show a false "unmuted"), and can't mute.
            guard AudioObjectHasProperty(dev, &ma), AudioObjectIsPropertySettable(dev, &ma, &msettable) == noErr,
                  msettable.boolValue else { return false }
            var m: UInt32 = v.muted ? 1 : 0
            guard AudioObjectSetPropertyData(dev, &ma, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m) == noErr
            else { return false }
        }
        var level = Float32(min(1, max(0, v.level)))
        return AudioObjectSetPropertyData(dev, &va, 0, nil, UInt32(MemoryLayout<Float32>.size), &level) == noErr
    }
}
