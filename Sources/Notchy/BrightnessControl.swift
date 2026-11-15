import CoreGraphics
import Darwin

/// Built-in display brightness via the private DisplayServices framework (dlopen'd once).
enum BrightnessControl {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private struct Symbols: @unchecked Sendable { let get: GetFn; let set: SetFn }

    private static let symbols: Symbols? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let g = dlsym(h, "DisplayServicesGetBrightness"),
              let s = dlsym(h, "DisplayServicesSetBrightness") else { return nil }
        return Symbols(get: unsafeBitCast(g, to: GetFn.self), set: unsafeBitCast(s, to: SetFn.self))
    }()

    static var isAvailable: Bool {
        symbols != nil && CGDisplayIsBuiltin(CGMainDisplayID()) != 0
    }

    static func current() -> Float? {
        guard isAvailable, let sym = symbols else { return nil }
        var v: Float = 0
        return sym.get(CGMainDisplayID(), &v) == 0 ? v : nil
    }

    static func set(_ level: Float) -> Bool {
        guard isAvailable, let sym = symbols else { return false }
        return sym.set(CGMainDisplayID(), min(1, max(0, level))) == 0
    }
}
