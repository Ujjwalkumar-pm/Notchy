import Foundation

/// Pop-up HUD state. Visible until 1.5 s after the most recent `show`.
public struct HUDState: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case volume, brightness }

    /// How long the pop-up stays after the last key press.
    private static let linger: TimeInterval = 1.5

    public private(set) var kind: Kind?
    public private(set) var level: Float
    public private(set) var muted: Bool
    private var lastShown: Date?

    public init() {
        kind = nil
        level = 0
        muted = false
        lastShown = nil
    }

    public mutating func show(_ kind: Kind, level: Float, muted: Bool, now: Date) {
        self.kind = kind
        self.level = level
        self.muted = muted
        lastShown = now
    }

    /// Time at which the pop-up hides, or nil if it has never been shown.
    public var hideAt: Date? {
        lastShown.map { $0.addingTimeInterval(Self.linger) }
    }

    public func visible(now: Date) -> Bool {
        guard let hideAt else { return false }
        return now < hideAt
    }
}
