import Foundation

/// Where a tab being dragged in the tab bar belongs now. Tabs sit in fixed slots of width
/// `slot` starting at x = 0; the dragged tab is at visible index `index` and the pointer at
/// `pointerX` (tab-bar coordinates). It moves one place each time the pointer crosses a
/// neighbour's midpoint, so moving back needs the pointer to cross the midpoint again.
public func tabDragTarget(from index: Int, pointerX: Double, slot: Double, count: Int) -> Int {
    guard count > 0, slot > 0 else { return index }
    var t = min(max(index, 0), count - 1)
    while t + 1 < count && pointerX > (Double(t + 1) + 0.5) * slot { t += 1 }
    while t - 1 >= 0 && pointerX < (Double(t - 1) + 0.5) * slot { t -= 1 }
    return t
}

/// Moves `tab` so it lands where the visible tab at `visibleIndex` is now (hidden tabs keep
/// their places in `tabOrder`). Unknown tab or index → unchanged.
public func movingVisibleTab(_ s: NotchySettings, _ tab: TabID, toVisibleIndex visibleIndex: Int) -> NotchySettings {
    let visible = visibleTabs(s)
    guard visible.indices.contains(visibleIndex),
          let from = s.tabOrder.firstIndex(of: tab),
          let to = s.tabOrder.firstIndex(of: visible[visibleIndex]) else { return s }
    return movingTab(s, from: from, to: to)
}

/// A press that moved less than this (pt) is a click, not a drag.
public let tabClickSlop: Double = 4

/// Settings → Tabs list drag: the row at `from` dragged vertically by `translation` (pt) in
/// a list of `count` rows spaced `stride` apart lands at the returned index. A move counts
/// once it passes half a row; the result is clamped to the list.
public func listDragTarget(from: Int, translation: Double, stride: Double, count: Int) -> Int {
    guard count > 0, stride > 0, translation.isFinite else { return min(max(from, 0), max(count - 1, 0)) }
    let steps = Int((translation / stride).rounded())
    return min(max(from + steps, 0), count - 1)
}
