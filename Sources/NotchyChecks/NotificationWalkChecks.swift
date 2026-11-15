import Foundation
import NotchyCore

func runNotificationWalkChecks() {
    let banner = notificationBannerSubrole
    // Fake AX tree: index → (node, children). `failing` simulates a timed-out AX call.
    func run(_ tree: [(WalkNode, [Int])], budget b: Int = 400, maxDepth: Int = 9, failing: Int? = nil)
        -> [BannerGroupInfo]? {
        var budget = b
        return walkNotificationGroups(0, budget: &budget, maxDepth: maxDepth) { i in
            i == failing ? nil : tree[i]
        }?.map(\.info)
    }
    // The verified banner layout: window > hosting > group > scroll area > banner(title, body, close).
    let bannerTree: [(WalkNode, [Int])] = [
        (WalkNode(role: "AXWindow", subrole: "AXSystemDialog"), [1]),
        (WalkNode(role: "AXGroup", subrole: "AXHostingView"), [2]),
        (WalkNode(role: "AXGroup"), [3, 8]),
        (WalkNode(role: "AXScrollArea"), [4]),
        (WalkNode(role: "AXGroup", subrole: banner, identifier: "U1"), [5, 6, 7]),
        (WalkNode(role: "AXStaticText", identifier: "title"), []),
        (WalkNode(role: "AXStaticText", identifier: "body"), []),
        (WalkNode(role: "AXButton"), []),
        (WalkNode(role: "AXGroup", identifier: "widgets-overlay-view"), []),
    ]
    check("walk.banner", run(bannerTree) == [BannerGroupInfo(id: "U1", subrole: banner, inList: false)])

    // The list: the scroll area also holds a heading and a "Clear all" button.
    let listTree: [(WalkNode, [Int])] = [
        (WalkNode(role: "AXWindow", subrole: "AXSystemDialog"), [1]),
        (WalkNode(role: "AXScrollArea"), [2, 3, 4, 5]),
        (WalkNode(role: "AXHeading"), []),
        (WalkNode(role: "AXGroup", subrole: banner, identifier: "L1"), []),
        (WalkNode(role: "AXGroup", subrole: notificationAlertSubrole, identifier: "L2"), []),
        (WalkNode(role: "AXButton"), []),
    ]
    let list = run(listTree)
    check("walk.listContainer", list?.count == 2 && list?.allSatisfy(\.inList) == true
          && bannerGroupsToReport(list ?? [], reported: []).isEmpty)

    // Budget runs out inside the scroll area before its other content is seen: fail closed.
    let cut = run(listTree.enumerated().map { i, n in i == 1 ? (n.0, [3, 2, 4, 5]) : n }, budget: 3)
    check("walk.budgetFailClosed", cut?.count == 1 && cut?.first?.inList == true)
    // Depth cut inside the container: fail closed as well.
    let deep: [(WalkNode, [Int])] = [
        (WalkNode(role: "AXScrollArea"), [1, 2]),
        (WalkNode(role: "AXGroup", subrole: banner, identifier: "D1"), []),
        (WalkNode(role: "AXGroup"), [3]),
        (WalkNode(role: "AXGroup"), []),
    ]
    check("walk.depthFailClosed", run(deep, maxDepth: 1)?.first?.inList == true
          && run(deep)?.first?.inList == false)

    // An AX timeout anywhere aborts the whole walk (nothing reported).
    check("walk.abortOnTimeout", run(bannerTree, failing: 6) == nil && run(bannerTree, failing: 8) == nil)
}
