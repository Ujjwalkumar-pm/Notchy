import Foundation

nonisolated(unsafe) var checkPassed = 0
nonisolated(unsafe) var checkFailures: [String] = []

func check(_ name: String, _ cond: @autoclosure () -> Bool) {
    if cond() { checkPassed += 1 } else { checkFailures.append(name) }
}
