/// Fill opacity of the notch panel background.
/// Closed: almost transparent. It sits behind the camera housing, so black adds nothing on the
/// real screen, but screenshots and screen recordings don't draw the hardware notch and show
/// a black block there. A fully clear window gets no hover events (the window server treats
/// alpha 0 as click-through), so keep a sliver of alpha.
/// Open: solid black.
public func notchFillOpacity(expanded: Bool) -> Double {
    expanded ? 1 : 0.01
}
