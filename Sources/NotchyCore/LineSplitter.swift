import Foundation

/// Splits a byte stream into lines on `\n`, carrying a partial line over between chunks.
/// A line longer than `maxBuffer` is dropped (including its remainder up to the next newline).
public struct LineSplitter: Sendable {
    private var buffer = Data()
    private var skipping = false
    private let maxBuffer: Int
    public init(maxBuffer: Int = 8 * 1024 * 1024) { self.maxBuffer = maxBuffer }

    public mutating func feed(_ chunk: Data) -> [Substring] {
        var out: [Substring] = []
        var rest = chunk[...]
        while let nl = rest.firstIndex(of: 0x0A) {
            let head = rest[rest.startIndex..<nl]
            rest = rest[rest.index(after: nl)...]
            if skipping { skipping = false; buffer.removeAll(); continue }
            buffer.append(contentsOf: head)
            if buffer.count <= maxBuffer, let s = String(data: buffer, encoding: .utf8), !s.isEmpty {
                out.append(Substring(s))
            }
            buffer.removeAll(keepingCapacity: true)
        }
        if !skipping {
            buffer.append(contentsOf: rest)
            if buffer.count > maxBuffer { buffer.removeAll(); skipping = true }
        }
        return out
    }
}
