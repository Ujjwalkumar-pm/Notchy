// Notchy - a personal macOS notch app.
//
// Derived from Atoll (DynamicIsland), itself derived from boring.notch.
// Original: reference/atoll/stage1/matters.swift (getClosedNotchSize)
// Modified for Notchy, 2026-11-13.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program (LICENSE at the repository root).
// If not, see <https://www.gnu.org/licenses/>.
import AppKit

/// Computes the physical notch rectangle in global screen coordinates.
/// Unlike Atoll, no extra width is added: the collapsed shape is exactly the notch.
struct NotchGeometry {
    static let fallbackSize = CGSize(width: 200, height: 32)

    /// The built-in (notched) screen if any, otherwise the main screen.
    @MainActor
    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// True when the screen has a camera notch (not the fallback rect).
    @MainActor
    static func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0 && screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
    }

    @MainActor
    static func notchRect(for screen: NSScreen) -> CGRect {
        let frame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            let height = screen.safeAreaInsets.top
            // x centred between the two auxiliary areas
            let x = left.maxX + (right.minX - left.maxX - width) / 2
            return CGRect(x: x, y: frame.maxY - height, width: width, height: height)
        }
        let size = fallbackSize
        return CGRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height,
                      width: size.width, height: size.height)
    }
}
