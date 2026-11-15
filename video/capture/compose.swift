// Compositor for the Notchy capture build's window recordings (video/capture/capture.py).
//
//   compose canvas <geometry.json> <notch|desk> <out.png>
//       The backdrop for a canvas preset: a generated abstract wallpaper, a drawn menu bar
//       and the black camera notch. Nothing from the real desktop.
//   compose shot <shotDir> <notch|desk> <outDir>
//       Resamples <shotDir>/frames.json to 30 fps and draws each frame's Notchy windows (and
//       the virtual pointer) over the canvas: <outDir>/frame-%05d.png and still.png (last frame).
//   compose grab <shotDir> <grab-name> <notch|desk> <out.png>
//       A real-screen grab (Glass, which only renders on screen) placed on the canvas.
//
// Presets (points, top-left screen coordinates, 2x pixels): notch = 960 x 540 centred on the
// notch (1920 x 1080 px); desk = 1280 x 720 (2560 x 1440 px).
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let scale: CGFloat = 2
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

struct Geometry: Decodable { let screen: [Double]; let notch: [Double]; let menuBar: Double }
struct WinShot: Decodable { let id: Int; let layer: Int; let x: Double; let y: Double; let w: Double; let h: Double; let file: String }
struct Frame: Decodable { let t: Double; let windows: [WinShot]; let pointer: [Double]?; let pointerDown: Bool; let statusIcon: Bool? }

func load<T: Decodable>(_ t: T.Type, _ path: String) -> T {
    try! JSONDecoder().decode(t, from: Data(contentsOf: URL(fileURLWithPath: path)))
}

func canvasRect(_ g: Geometry, _ preset: String) -> CGRect {
    let cx = g.notch[0] + g.notch[2] / 2
    return preset == "desk" ? CGRect(x: cx - 640, y: 0, width: 1280, height: 720)
                            : CGRect(x: cx - 480, y: 0, width: 960, height: 540)
}

func makeContext(_ size: CGSize) -> CGContext {
    CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
              bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func loadImage(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func save(_ img: CGImage, _ path: String) {
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil)
    CGImageDestinationFinalize(d)
}

// MARK: Backdrop

/// Wallpaper over the whole screen (so both presets crop the same art), in screen points.
func drawWallpaper(_ c: CGContext, screen: CGSize, canvas: CGRect) {
    // Work in screen points with a top-left origin.
    c.saveGState()
    c.scaleBy(x: scale, y: scale)
    c.translateBy(x: -canvas.minX, y: canvas.height + canvas.minY)
    c.scaleBy(x: 1, y: -1)
    let base = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.10, green: 0.13, blue: 0.24, alpha: 1),
        CGColor(red: 0.17, green: 0.24, blue: 0.36, alpha: 1),
        CGColor(red: 0.30, green: 0.36, blue: 0.44, alpha: 1)] as CFArray, locations: [0, 0.55, 1])!
    c.drawLinearGradient(base, start: CGPoint(x: 0, y: 0), end: CGPoint(x: screen.width * 0.3, y: screen.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    func blob(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ rgb: (CGFloat, CGFloat, CGFloat), _ a: CGFloat) {
        let g = CGGradient(colorsSpace: cs, colors: [CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: a),
                                                     CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 0)] as CFArray,
                           locations: [0, 1])!
        c.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y),
                             endRadius: r, options: [])
    }
    let w = screen.width, h = screen.height
    blob(w * 0.22, h * 0.30, w * 0.42, (0.36, 0.42, 0.78), 0.55)   // periwinkle, upper left
    blob(w * 0.78, h * 0.22, w * 0.40, (0.20, 0.55, 0.62), 0.50)   // teal, upper right
    blob(w * 0.55, h * 0.95, w * 0.55, (0.93, 0.55, 0.45), 0.45)   // coral glow, bottom
    blob(w * 0.08, h * 0.90, w * 0.35, (0.55, 0.38, 0.70), 0.40)   // violet, lower left
    blob(w * 0.50, h * 0.48, w * 0.30, (0.65, 0.72, 0.88), 0.18)   // soft light, centre
    c.restoreGState()
}

func drawText(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight, right: Bool = false) -> CGFloat {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                .foregroundColor: NSColor.white.withAlphaComponent(0.95)]
    let a = NSAttributedString(string: s, attributes: attrs)
    let sz = a.size()
    a.draw(at: CGPoint(x: right ? p.x - sz.width : p.x, y: p.y - sz.height / 2))
    return sz.width
}

func drawSymbol(_ name: String, center: CGPoint, height: CGFloat) -> CGFloat {
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: height, weight: .regular)) else { return 0 }
    let tinted = NSImage(size: img.size, flipped: false) { r in
        img.draw(in: r)
        NSColor.white.withAlphaComponent(0.95).set()
        r.fill(using: .sourceAtop)
        return true
    }
    tinted.draw(in: CGRect(x: center.x - img.size.width / 2, y: center.y - img.size.height / 2,
                           width: img.size.width, height: img.size.height))
    return img.size.width
}

/// Menu bar band, generic menus (no logo), a few status glyphs and a clock, and the camera
/// notch. Returns the left edge of the drawn status items (points, canvas coordinates).
@discardableResult
func drawMenuBar(_ c: CGContext, g: Geometry, canvas: CGRect) -> CGFloat {
    let mb = CGFloat(g.menuBar)
    let H = canvas.height
    c.saveGState()
    c.scaleBy(x: scale, y: scale)
    c.setFillColor(CGColor(red: 0.04, green: 0.05, blue: 0.10, alpha: 0.30))
    c.fill(CGRect(x: 0, y: H - mb, width: canvas.width, height: mb))
    let ns = NSGraphicsContext(cgContext: c, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ns
    let y = H - mb / 2
    var x: CGFloat = 18
    x += drawText("Finder", at: CGPoint(x: x, y: y), size: 13, weight: .bold) + 20
    for m in ["File", "Edit", "View", "Go", "Window", "Help"] {
        x += drawText(m, at: CGPoint(x: x, y: y), size: 13, weight: .regular) + 20
    }
    var r = canvas.width - 14
    r -= drawText("Mon 16 Nov  9:41", at: CGPoint(x: r, y: y), size: 13, weight: .regular, right: true) + 16
    r -= drawSymbol("battery.75percent", center: CGPoint(x: r - 14, y: y), height: 13) + 14
    r -= drawSymbol("wifi", center: CGPoint(x: r - 10, y: y), height: 13) + 14
    NSGraphicsContext.restoreGraphicsState()
    // Camera notch (black, rounded bottom corners).
    let nx = CGFloat(g.notch[0]) - canvas.minX, nw = CGFloat(g.notch[2]), nh = CGFloat(g.notch[3])
    let rad: CGFloat = 8
    let p = CGMutablePath()
    p.move(to: CGPoint(x: nx, y: H)); p.addLine(to: CGPoint(x: nx, y: H - nh + rad))
    p.addArc(tangent1End: CGPoint(x: nx, y: H - nh), tangent2End: CGPoint(x: nx + rad, y: H - nh), radius: rad)
    p.addLine(to: CGPoint(x: nx + nw - rad, y: H - nh))
    p.addArc(tangent1End: CGPoint(x: nx + nw, y: H - nh), tangent2End: CGPoint(x: nx + nw, y: H - nh + rad), radius: rad)
    p.addLine(to: CGPoint(x: nx + nw, y: H)); p.closeSubpath()
    c.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    c.addPath(p); c.fillPath()
    c.restoreGState()
    return r
}

func makeCanvas(_ g: Geometry, _ preset: String) -> (CGImage, CGFloat) {
    let canvas = canvasRect(g, preset)
    let c = makeContext(canvas.size)
    drawWallpaper(c, screen: CGSize(width: g.screen[0], height: g.screen[1]), canvas: canvas)
    let right = drawMenuBar(c, g: g, canvas: canvas)
    return (c.makeImage()!, right)
}

// MARK: Pointer

func drawPointer(_ c: CGContext, at p: CGPoint, down: Bool) {
    // p: canvas points, top-left origin; drawn in a flipped frame so the tip sits on p.
    c.saveGState()
    c.translateBy(x: p.x * scale, y: c.height.cg - p.y * scale)
    let s = scale * (down ? 0.9 : 1)
    c.scaleBy(x: s, y: -s)
    let path = CGMutablePath()
    path.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 17), CGPoint(x: 4.2, y: 13.1),
                            CGPoint(x: 7.1, y: 19.6), CGPoint(x: 9.6, y: 18.5), CGPoint(x: 6.8, y: 12.2),
                            CGPoint(x: 12.3, y: 12.2)])
    path.closeSubpath()
    c.setShadow(offset: CGSize(width: 0, height: -1.5 * scale), blur: 3 * scale,
                color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
    c.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    c.addPath(path); c.setLineWidth(2.2); c.setLineJoin(.round)
    c.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1)); c.strokePath()
    c.setShadow(offset: .zero, blur: 0, color: nil)
    c.addPath(path); c.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); c.fillPath()
    c.restoreGState()
}

extension Int { var cg: CGFloat { CGFloat(self) } }

// MARK: Shot

func composeShot(dir: String, preset: String, out: String) {
    let g = load(Geometry.self, dir + "/geometry.json")
    let frames = load([Frame].self, dir + "/frames.json")
    let canvas = canvasRect(g, preset)
    let (bg, statusRight) = makeCanvas(g, preset)
    try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    guard let last = frames.last else { return }
    let count = Int((last.t * 30).rounded(.down)) + 1
    // Nearest recorded frame at or before each output time (+ half a frame).
    var pick: [Int] = []
    var j = 0
    for i in 0..<count {
        let t = Double(i) / 30 + 0.5 / 30
        while j + 1 < frames.count && frames[j + 1].t <= t { j += 1 }
        pick.append(j)
    }
    let lock = NSLock()
    var cache: [Int: CGImage] = [:]
    func render(_ f: Frame) -> CGImage {
        let c = makeContext(canvas.size)
        c.draw(bg, in: CGRect(x: 0, y: 0, width: c.width, height: c.height))
        for w in f.windows {
            guard let img = loadImage(dir + "/" + w.file) else { continue }
            var x = CGFloat(w.x) - canvas.minX
            let y = CGFloat(w.y) - canvas.minY
            if w.layer == 25 { x = statusRight - 6 - CGFloat(w.w) } // status item: beside the drawn extras
            let rect = CGRect(x: x * scale, y: c.height.cg - (y + CGFloat(w.h)) * scale,
                              width: CGFloat(w.w) * scale, height: CGFloat(w.h) * scale)
            c.saveGState()
            if w.layer == 0 {
                c.setShadow(offset: CGSize(width: 0, height: -18 * scale), blur: 48 * scale,
                            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
            } else if w.layer >= 100 {
                c.setShadow(offset: CGSize(width: 0, height: -6 * scale), blur: 18 * scale,
                            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.4))
            }
            c.draw(img, in: rect)
            c.restoreGState()
        }
        if f.statusIcon == true {
            // Notchy's menu bar icon (its own symbol, as StatusMenu.swift sets it), left of the extras.
            let ns = NSGraphicsContext(cgContext: c, flipped: false)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
            c.saveGState(); c.scaleBy(x: scale, y: scale)
            _ = drawSymbol("rectangle.topthird.inset.filled", center: CGPoint(x: statusRight - 16, y: canvas.height - CGFloat(g.menuBar) / 2), height: 13)
            c.restoreGState(); NSGraphicsContext.restoreGraphicsState()
        }
        if let p = f.pointer {
            drawPointer(c, at: CGPoint(x: CGFloat(p[0]) - canvas.minX, y: CGFloat(p[1]) - canvas.minY), down: f.pointerDown)
        }
        return c.makeImage()!
    }
    DispatchQueue.concurrentPerform(iterations: count) { i in
        let fi = pick[i]
        lock.lock(); let cached = cache[fi]; lock.unlock()
        let img: CGImage
        if let cached { img = cached } else {
            img = render(frames[fi])
            lock.lock(); cache[fi] = img; if cache.count > 64 { cache.removeAll() }; lock.unlock()
        }
        save(img, String(format: "%@/frame-%05d.png", out, i + 1))
    }
    try? FileManager.default.removeItem(atPath: out + "/still.png")
    try? FileManager.default.copyItem(atPath: String(format: "%@/frame-%05d.png", out, count), toPath: out + "/still.png")
    print("\(out): \(count) frames, \(Int(canvas.width * scale))x\(Int(canvas.height * scale))")
}

func composeGrab(dir: String, name: String, preset: String, out: String) {
    let g = load(Geometry.self, dir + "/geometry.json")
    let req = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "\(dir)/grab-\(name).json"))) as! [String: Any]
    let r = (req["rect"] as! [Double]).map { CGFloat($0) }
    let canvas = canvasRect(g, preset)
    let (bg, _) = makeCanvas(g, preset)
    let c = makeContext(canvas.size)
    c.draw(bg, in: CGRect(x: 0, y: 0, width: c.width, height: c.height))
    if let img = loadImage("\(dir)/grab-\(name).png") {
        c.draw(img, in: CGRect(x: (r[0] - canvas.minX) * scale, y: c.height.cg - (r[1] - canvas.minY + r[3]) * scale,
                               width: r[2] * scale, height: r[3] * scale))
    }
    save(c.makeImage()!, out)
    print(out)
}

let a = CommandLine.arguments
switch a.count > 1 ? a[1] : "" {
case "canvas": save(makeCanvas(load(Geometry.self, a[2]), a[3]).0, a[4])
case "shot": composeShot(dir: a[2], preset: a[3], out: a[4])
case "grab": composeGrab(dir: a[2], name: a[3], preset: a[4], out: a[5])
default: print("usage: compose canvas|shot|grab ..."); exit(2)
}
