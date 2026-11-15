import Foundation
import NotchyCore

func runTabDragChecks() {
    // Slots of 40: centres at 20, 60, 100, 140.
    check("tabdrag.stayBeforeMidpoint", tabDragTarget(from: 0, pointerX: 59, slot: 40, count: 4) == 0)
    check("tabdrag.movePastMidpoint", tabDragTarget(from: 0, pointerX: 61, slot: 40, count: 4) == 1)
    check("tabdrag.multiStep", tabDragTarget(from: 0, pointerX: 141, slot: 40, count: 4) == 3)
    check("tabdrag.clampRight", tabDragTarget(from: 3, pointerX: 900, slot: 40, count: 4) == 3)
    check("tabdrag.clampLeft", tabDragTarget(from: 2, pointerX: -50, slot: 40, count: 4) == 0)
    // Hysteresis: after moving to 1 the pointer at 50 (between centres 20 and 60) keeps it there.
    check("tabdrag.hysteresis", tabDragTarget(from: 1, pointerX: 50, slot: 40, count: 4) == 1)
    check("tabdrag.backPastMidpoint", tabDragTarget(from: 1, pointerX: 19, slot: 40, count: 4) == 0)

    // Settings list: rows 37 pt apart.
    check("listdrag.belowHalfRow", listDragTarget(from: 1, translation: 18, stride: 37, count: 4) == 1)
    check("listdrag.pastHalfRow", listDragTarget(from: 1, translation: 19, stride: 37, count: 4) == 2)
    check("listdrag.multiRowUp", listDragTarget(from: 3, translation: -75, stride: 37, count: 4) == 1)
    check("listdrag.clampEnds", listDragTarget(from: 2, translation: 500, stride: 37, count: 4) == 3
          && listDragTarget(from: 1, translation: -500, stride: 37, count: 4) == 0)

    let d = NotchySettings.defaults
    check("tabdrag.visibleMove",
          movingVisibleTab(d, .music, toVisibleIndex: 2).tabOrder == [.claude, .alerts, .music, .calendar])
    var hidden = d
    hidden.enabledTabs = [.music, .claude, .calendar] // alerts hidden, keeps its slot
    check("tabdrag.visibleMoveSkipsHidden",
          movingVisibleTab(hidden, .music, toVisibleIndex: 2).tabOrder == [.claude, .alerts, .calendar, .music])
    check("tabdrag.badIndex", movingVisibleTab(d, .music, toVisibleIndex: 9) == d)
}
