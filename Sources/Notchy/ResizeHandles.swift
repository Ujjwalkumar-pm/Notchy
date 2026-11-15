import AppKit

import NotchyCore

/// An invisible 6 pt drag zone on the left, right or bottom edge of the panel.
/// Width drags resize both sides symmetrically (the panel stays centred on the notch);
/// the bottom zone changes height. The panel saves the new size on mouse-up.
final class ResizeHandle: NSView {
    enum Edge { case left, right, bottom }

    let edge: Edge
    /// Called on mouse-down; returns the size to start from (the size currently showing).
    var onBegin: (() -> CGSize)?
    /// Live size while dragging (not yet saved).
    var onDrag: ((CGSize) -> Void)?
    /// Width change per point dragged: 2 for a centred panel (grows both sides), 1 for one
    /// anchored on an edge. Read at drag start.
    var widthFactor: () -> CGFloat = { 2 }
    private var factor: CGFloat = 2
    /// Pointer entered or left this zone (the panel re-checks hover expansion).
    var onHoverChange: ((CGPoint) -> Void)?
    /// Mouse-up: the final size, or nil if the size didn't change (a plain click saves nothing).
    var onEnd: ((CGSize?) -> Void)?

    private var startMouse: CGPoint = .zero
    private var startSize: CGSize = .zero
    private var lastSize: CGSize = .zero
    private var dragging = false
    private var area: NSTrackingArea?

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private var cursor: NSCursor { edge == .bottom ? .resizeUpDown : .resizeLeftRight }

    /// Adds this zone to `container`; the container calls `relayout()` on every resize.
    func install(in container: NSView) {
        autoresizingMask = []
        container.addSubview(self)
        relayout()
    }

    /// Pins this zone to its edge. Thickness is 6 pt, or a quarter of the panel's width
    /// (side zones) / height (bottom zone) if smaller, so a tiny panel keeps a hoverable middle.
    func relayout() {
        guard let b = superview?.bounds else { return }
        switch edge {
        case .left:
            frame = CGRect(x: 0, y: 0, width: resizeZoneThickness(dimension: b.width), height: b.height)
        case .right:
            let t = resizeZoneThickness(dimension: b.width)
            frame = CGRect(x: b.width - t, y: 0, width: t, height: b.height)
        case .bottom:
            // Origin is bottom-left in AppKit; the side zones win at the corners (added later).
            frame = CGRect(x: 0, y: 0, width: b.width, height: resizeZoneThickness(dimension: b.height))
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // The panel is never key, so cursor rects don't fire; a tracking area sets the cursor instead.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero,
                               options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(a)
        area = a
    }
    override func cursorUpdate(with event: NSEvent) { cursor.set() }
    override func mouseEntered(with event: NSEvent) {
        cursor.set()
        onHoverChange?(screenPoint(event))
    }
    override func mouseExited(with event: NSEvent) {
        if !dragging { NSCursor.arrow.set() }
        onHoverChange?(screenPoint(event))
    }

    private func screenPoint(_ event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }

    /// Whether a screen point is over this zone.
    func contains(screenPoint p: CGPoint) -> Bool {
        guard let window, !isHidden else { return false }
        return window.convertToScreen(convert(bounds, to: nil)).contains(p)
    }

    override func rightMouseDown(with event: NSEvent) {
        superview?.rightMouseDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        dragging = true
        startMouse = NSEvent.mouseLocation
        startSize = onBegin?() ?? frame.size
        factor = widthFactor()
        lastSize = startSize
        cursor.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        let p = NSEvent.mouseLocation
        let dx = p.x - startMouse.x, dy = p.y - startMouse.y
        var s = startSize
        switch edge {
        case .right: s.width = startSize.width + factor * dx
        case .left: s.width = startSize.width - factor * dx
        case .bottom: s.height = startSize.height - dy   // screen y grows upward
        }
        // Floor 1 pt, whole points, no upper cap.
        s = CGSize(width: max(1, s.width.rounded()), height: max(1, s.height.rounded()))
        guard s != lastSize else { return }
        lastSize = s
        onDrag?(s)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        cursor.set()
        onEnd?(lastSize == startSize ? nil : lastSize)
    }
}
