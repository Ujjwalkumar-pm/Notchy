import Foundation

/// Adapter restart backoff: 1 s, 5 s, 30 s, then give up.
public struct RestartPolicy: Sendable {
    private var attempt = 0
    private static let delays: [TimeInterval] = [1, 5, 30]
    public init() {}

    public mutating func nextDelay() -> TimeInterval? {
        guard attempt < Self.delays.count else { return nil }
        defer { attempt += 1 }
        return Self.delays[attempt]
    }

    public mutating func reset() { attempt = 0 }
}
