import Foundation
import NotchyCore

func runNotchStyleChecks() {
    // collapsedIsInvisible: the closed panel must not show as a black block (screenshots and
    // recordings don't include the hardware notch), but must keep a little alpha so the
    // window server still delivers hover to it.
    let c = notchFillOpacity(expanded: false)
    check("collapsedFill.invisible", c <= 0.02)
    check("collapsedFill.hoverable", c > 0)
    check("expandedFill.solid", notchFillOpacity(expanded: true) == 1)
}
