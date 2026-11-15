import Foundation

/// The attributes a Notification Center walk reads per element.
public struct WalkNode: Equatable, Sendable {
    public var role: String
    public var subrole: String?
    public var identifier: String?

    public init(role: String, subrole: String? = nil, identifier: String? = nil) {
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
    }
}

/// Containers whose groups are list content when they also hold anything else.
let walkContainerRoles: Set<String> = ["AXScrollArea", "AXList", "AXOutline", "AXTable"]
/// Non-banner content: its presence in a container means the Notification Center list.
let walkOtherContentRoles: Set<String> = ["AXStaticText", "AXHeading", "AXButton", "AXTextField",
                                          "AXCheckBox", "AXMenuButton"]

/// Collects the innermost `AXNotificationCenter*` groups under `root`, in walk order, with a
/// shared node `budget` and `maxDepth`. `read` returns the node's attributes and children, or
/// nil when Accessibility timed out / could not complete — the whole walk is then aborted
/// (returns nil) so nothing half-read is reported.
///
/// A container (scroll area / list / outline / table) whose subtree holds non-banner content
/// (text, headings, buttons, widgets) outside notification groups marks its groups `inList`.
/// Fail closed: a container whose subtree was cut short (budget or depth) also marks them.
public func walkNotificationGroups<N>(_ root: N, budget: inout Int, maxDepth: Int,
                                      read: (N) -> (node: WalkNode, children: [N])?)
    -> [(element: N, info: BannerGroupInfo)]? {
    var out: [(element: N, info: BannerGroupInfo)] = []
    var aborted = false

    /// Returns (other content, truncated).
    func visit(_ e: N, depth: Int) -> (Bool, Bool) {
        if aborted { return (false, true) }
        guard budget > 0, depth <= maxDepth else { return (false, true) }
        budget -= 1
        guard let r = read(e) else {
            aborted = true
            return (false, true)
        }
        if r.node.subrole?.hasPrefix("AXNotificationCenter") == true {
            let start = out.count
            for c in r.children { _ = visit(c, depth: depth + 1) }
            if out.count == start {
                out.append((e, BannerGroupInfo(id: r.node.identifier, subrole: r.node.subrole, inList: false)))
            }
            return (false, false)
        }
        let ident = r.node.identifier ?? ""
        var other = walkOtherContentRoles.contains(r.node.role)
            || (ident.contains("widget") && ident != "widgets-overlay-view")
        var truncated = false
        let start = out.count
        for c in r.children {
            let (o, t) = visit(c, depth: depth + 1)
            other = other || o
            truncated = truncated || t
            if aborted { break }
        }
        if walkContainerRoles.contains(r.node.role) && (other || truncated) {
            for i in start..<out.count { out[i].info.inList = true }
        }
        return (other, truncated)
    }

    _ = visit(root, depth: 0)
    return aborted ? nil : out
}
