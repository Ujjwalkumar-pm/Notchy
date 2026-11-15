#if NOTCHY_CAPTURE
// Capture build only (`-D NOTCHY_CAPTURE`, scripts/capture-build.sh). Never in the release app.
//
// Drives the real Notchy UI through scripted demo states for the launch videos and records
// Notchy's own windows (no Screen Recording permission needed for an app's own windows).
// Demo data only: no hook server, Claude settings, calendar, Now Playing, Notification
// Center, Dock, device or Focus input is ever read. No synthetic events are posted: the
// "pointer" is a virtual position the panel reads instead of the real one.
//
// Launch: NotchyCapture.app --args --capture-shot <name> --capture-out <dir> [--capture-backdrop <png>]
// Output: <dir>/raw/*.png (window images), <dir>/frames.json, <dir>/geometry.json.
import AppKit
import SwiftUI
import Combine
import ImageIO
import UniformTypeIdentifiers
import NotchyCore

/// State the views and the panel read instead of the real pointer / gestures.
@MainActor
final class CaptureState: ObservableObject {
    static let shared = CaptureState()
    /// Virtual pointer (Cocoa screen coordinates). Read by the panel's hover, arming and
    /// content gates. Not published: the panel polls / is resynced by the harness.
    var pointer: CGPoint?
    var pointerVisible = false
    var pointerDown = false
    /// Scrubber drag fraction (0…1) while the virtual pointer "drags" it; nil otherwise.
    @Published var scrub: Double?
    /// Pointer resting on the scrubber (shows the knob).
    @Published var scrubHover = false
    /// Settings sidebar selection forced by the harness.
    @Published var settingsSection: SettingsSection?
    /// Demo permission states for the welcome checklist (missing = not determined).
    var permissions: [Permission: PermissionState] = [:]
    /// The live scrubber bar in hosting-view coordinates (top-left origin).
    var scrubberRect: CGRect?
}

@MainActor
struct CaptureContext {
    let app: AppModel
    let panel: NotchPanel
    let settings: SettingsWindowController
    let welcome: WelcomeWindowController
    let statusMenu: StatusMenu
    let screen: NSScreen
}

// MARK: - Recorder

/// Records every on-screen window of this process (except the backdrop) at 30 Hz on the main
/// run loop (common modes, so it keeps running during menu tracking). PNG encoding runs on a
/// background queue.
@MainActor
final class CaptureRecorder {
    struct WindowShot: Encodable {
        let id: Int, layer: Int, x: Double, y: Double, w: Double, h: Double, file: String
    }
    struct Frame: Encodable {
        let t: Double
        let windows: [WindowShot]
        let pointer: [Double]?
        let pointerDown: Bool
        /// Settings → Menu bar icon is on. Status items are not windows of this process on
        /// current macOS, so the compositor draws the icon's symbol in its menu bar.
        let statusIcon: Bool
    }

    private let dir: URL
    private let pid = ProcessInfo.processInfo.processIdentifier
    private var timer: Timer?
    private var t0 = Date()
    private var frames: [Frame] = []
    private var n = 0
    private let encodeQueue = DispatchQueue(label: "capture.encode", qos: .userInitiated, attributes: .concurrent)
    private let group = DispatchGroup()
    var excluded: Set<Int> = []
    var statusIcon: () -> Bool = { false }
    let screenHeight: CGFloat

    init(dir: URL, screenHeight: CGFloat) {
        self.dir = dir
        self.screenHeight = screenHeight
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("raw"), withIntermediateDirectories: true)
    }

    func start() {
        t0 = Date()
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.002
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    private func tick() {
        let t = Date().timeIntervalSince(t0)
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        var shots: [WindowShot] = []
        // Front to back in the list; stored back to front for drawing.
        for w in list.reversed() {
            guard (w[kCGWindowOwnerPID as String] as? Int32) == pid,
                  let id = w[kCGWindowNumber as String] as? Int, !excluded.contains(id),
                  let layer = w[kCGWindowLayer as String] as? Int,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(id),
                                                    [.boundsIgnoreFraming, .bestResolution]),
                  img.width > 1, img.height > 1 else { continue }
            let file = String(format: "raw/%05d-%d.png", n, id)
            let url = dir.appendingPathComponent(file)
            group.enter()
            encodeQueue.async { [group] in
                if let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(d, img, nil)
                    CGImageDestinationFinalize(d)
                }
                group.leave()
            }
            shots.append(WindowShot(id: id, layer: layer, x: Double(b["X"] ?? 0), y: Double(b["Y"] ?? 0),
                                    w: Double(b["Width"] ?? 0), h: Double(b["Height"] ?? 0), file: file))
        }
        let s = CaptureState.shared
        // Pointer in top-left (CG) coordinates.
        let p = s.pointerVisible ? s.pointer.map { [Double($0.x), Double(screenHeight - $0.y)] } : nil
        frames.append(Frame(t: t, windows: shots, pointer: p, pointerDown: s.pointerDown, statusIcon: statusIcon()))
        n += 1
    }

    func finish(_ done: @escaping @MainActor () -> Void) {
        timer?.invalidate()
        timer = nil
        let frames = self.frames, dir = self.dir
        group.notify(queue: .main) {
            let enc = JSONEncoder()
            if let data = try? enc.encode(frames) {
                try? data.write(to: dir.appendingPathComponent("frames.json"))
            }
            MainActor.assumeIsolated { done() }
        }
    }
}

// MARK: - Harness

@MainActor
enum CaptureHarness {
    private static var ctx: CaptureContext!
    private static var recorder: CaptureRecorder?
    private static var outDir = URL(fileURLWithPath: "/tmp/notchy-capture-out")
    private static var backdropWindow: NSWindow?
    private static var menuObserver: NSObjectProtocol?
    private static var trackedMenu: NSMenu?
    private static var pointerWork: [DispatchWorkItem] = []

    static func start(_ c: CaptureContext) {
        ctx = c
        let args = CommandLine.arguments
        func arg(_ k: String) -> String? { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        let shot = arg("--capture-shot") ?? "closed-notch"
        if let o = arg("--capture-out") { outDir = URL(fileURLWithPath: o) }
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        writeGeometry()
        prepareScratchClaudeSettings()
        loadDemoData()
        CaptureState.shared.pointer = offPointer
        CaptureState.shared.pointerVisible = false
        ctx.panel.captureResync()
        guard let script = shots[shot] else {
            notchyLog.error("Capture: unknown shot \(shot, privacy: .public)")
            NSApp.terminate(nil)
            return
        }
        if let bd = arg("--capture-backdrop") { showBackdrop(bd) }
        script.setup()
        // Let SwiftUI lay out and the panel settle before recording.
        after(script.settle) {
            let rec = CaptureRecorder(dir: outDir, screenHeight: ctx.screen.frame.height)
            if let b = backdropWindow { rec.excluded.insert(b.windowNumber) }
            rec.statusIcon = { ctx.app.settings.value.menuBarIcon }
            recorder = rec
            rec.start()
            for (t, step) in script.steps { after(t, step) }
            after(script.duration) {
                rec.finish {
                    try? "done".write(to: outDir.appendingPathComponent("DONE"), atomically: true, encoding: .utf8)
                    NSApp.terminate(nil)
                }
            }
        }
    }

    // MARK: Geometry

    static var notch: CGRect { ctx.panel.notchRect }
    static var top: CGFloat { ctx.screen.frame.maxY }
    static var offPointer: CGPoint { CGPoint(x: notch.midX + 300, y: top - 470) }

    private static func writeGeometry() {
        let s = ctx.screen
        let g: [String: Any] = [
            "screen": [s.frame.width, s.frame.height],
            "scale": s.backingScaleFactor,
            // Notch in top-left coordinates.
            "notch": [notch.minX, s.frame.maxY - notch.maxY, notch.width, notch.height],
            "menuBar": s.frame.maxY - s.visibleFrame.maxY,
        ]
        if let d = try? JSONSerialization.data(withJSONObject: g, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: outDir.appendingPathComponent("geometry.json"))
        }
    }

    /// The capture build's Claude settings are a scratch file with Notchy's hooks in it, so
    /// Settings → General reads "Installed" (the user's ~/.claude is never touched).
    private static func prepareScratchClaudeSettings() {
        let url = Lifecycle.claudeSettingsURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("{}".utf8).write(to: url)
        _ = Lifecycle.installer.install(now: Date())
    }

    // MARK: Demo data

    static let teams = "Microsoft Teams"
    static let outlook = "Microsoft Outlook"

    private static func loadDemoData() {
        let app = ctx.app
        app.settings.update { s in
            s = NotchySettings(hasSeenWelcome: true)
        }
        app.captureSetAXTrusted(true)
        app.captureSetDockCounts([teams: 3, outlook: 5])
        // Claude sessions through the real hook-event path.
        hook(["session_id": "demo-web", "cwd": "/Users/demo/Projects/web-app", "hook_event_name": "SessionStart"])
        hook(["session_id": "demo-api", "cwd": "/Users/demo/Projects/api-server", "hook_event_name": "SessionStart"])
        hook(["session_id": "demo-api", "cwd": "/Users/demo/Projects/api-server", "hook_event_name": "UserPromptSubmit"])
        hook(["session_id": "demo-api", "cwd": "/Users/demo/Projects/api-server", "hook_event_name": "PreToolUse",
              "tool_name": "Edit"])
        // Now playing: a demo track with generated artwork.
        app.nowPlaying.captureSet(NowPlayingInfo(title: "Golden Hour Drive", artist: "The Demo Band",
                                                 artwork: demoArtwork(), isPlaying: true, bundleId: nil,
                                                 duration: 214, elapsed: 71, elapsedAt: Date(), rate: 1, shuffle: false))
        // Alerts: oldest first (the list shows newest first).
        let now = Date()
        let rows: [(String, String, String, Double)] = [
            (outlook, "Priya S", "Re: Q4 roadmap, notes attached", 52),
            (teams, "Design team", "Ana: new mockups are in the channel", 41),
            (outlook, "Rahul M", "Invoice for October", 33),
            (teams, "Rahul M", "Can you review the API PR before standup?", 24),
            (outlook, "Ana K", "Offsite agenda (draft)", 15),
            (teams, "Priya S", "Pushed the fix to web-app", 7),
            (outlook, "Team calendar", "Sprint planning moved to 3:00 PM", 4),
            (teams, "Rahul M", "Thanks, merging now", 1),
        ]
        for (i, r) in rows.enumerated() {
            app.captureAddAlert(AlertItem(id: "demo-\(i)", app: r.0, title: r.1, body: r.2,
                                          at: now.addingTimeInterval(-r.3 * 60), device: false))
        }
        let ap = alertItemFor(.bluetooth(name: "AirPods Pro", connected: true, battery: nil, left: 82, right: 79, case: 64),
                              now: now.addingTimeInterval(-19 * 60))
        app.captureAddAlert(ap)
        // Calendar: demo meetings today and tomorrow.
        // The Calendar tab runs on a demo clock (9:41 today) so its times match the drawn menu bar.
        let demoNow = Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: now)!
        app.calendar.captureSet(meetings: demoMeetings(now: demoNow), now: demoNow, calendars: [
            .init(id: "demo-work", title: "Work", colorHex: "#3B82F6", source: "Exchange"),
            .init(id: "demo-team", title: "Team events", colorHex: "#A855F7", source: "Exchange"),
            .init(id: "demo-home", title: "Personal", colorHex: "#22C55E", source: "iCloud"),
            .init(id: "demo-hol", title: "Holidays", colorHex: "#F97316", source: "Other"),
        ])
    }

    static func demoMeetings(now: Date) -> [MeetingInfo] {
        let cal = Calendar.current
        let link = URL(string: "https://teams.microsoft.com/l/meetup-join/demo")
        let start = now.addingTimeInterval(5 * 60)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        func at(_ d: Date, _ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: d)! }
        var out = [
            MeetingInfo(id: "demo-m1", title: "Design review", start: start, end: start.addingTimeInterval(30 * 60),
                        allDay: false, calendarColorHex: "#3B82F6", joinURL: link,
                        attendees: ["Priya S", "Rahul M", "Ana K"], calendarTitle: "Work"),
            MeetingInfo(id: "demo-m2", title: "Sprint planning", start: at(now, 11, 0),
                        end: at(now, 11, 45), allDay: false, calendarColorHex: "#A855F7",
                        joinURL: URL(string: "https://teams.microsoft.com/l/meetup-join/demo2"),
                        attendees: ["Rahul M", "Ana K"], calendarTitle: "Team events"),
            MeetingInfo(id: "demo-m3", title: "1:1 with Priya", start: at(tomorrow, 10, 0), end: at(tomorrow, 10, 30),
                        allDay: false, calendarColorHex: "#3B82F6", joinURL: nil, attendees: ["Priya S"],
                        calendarTitle: "Work"),
            MeetingInfo(id: "demo-m4", title: "Team lunch", start: at(tomorrow, 13, 0), end: at(tomorrow, 14, 0),
                        allDay: false, calendarColorHex: "#22C55E", joinURL: nil, attendees: [],
                        calendarTitle: "Personal"),
        ]
        out.sort { $0.start < $1.start }
        return out
    }

    private static func hook(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj),
              let e = try? JSONDecoder().decode(HookEvent.self, from: d) else { return }
        ctx.app.handle(e)
    }

    private static var pendingApproval: UUID?

    /// A demo approval request through the real permission path; its reply goes nowhere.
    static func requestApproval() {
        let obj: [String: Any] = ["session_id": "demo-api", "cwd": "/Users/demo/Projects/api-server",
                                  "hook_event_name": "PermissionRequest", "tool_name": "Bash",
                                  "tool_input": ["command": "npm test", "description": "Run the test suite"]]
        guard let d = try? JSONSerialization.data(withJSONObject: obj),
              let e = try? JSONDecoder().decode(HookEvent.self, from: d) else { return }
        ctx.app.handlePermission(e) { _ in }
        pendingApproval = ctx.app.approvals.current?.id
    }

    /// Generated cover art: a warm dusk gradient, a sun and a road (no third-party art).
    static func demoArtwork() -> Data? {
        let n = 400
        guard let c = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let sky = CGGradient(colorsSpace: cs, colors: [
            CGColor(red: 0.16, green: 0.10, blue: 0.36, alpha: 1),
            CGColor(red: 0.85, green: 0.33, blue: 0.42, alpha: 1),
            CGColor(red: 1.00, green: 0.66, blue: 0.36, alpha: 1)] as CFArray, locations: [0, 0.6, 1])!
        c.drawLinearGradient(sky, start: CGPoint(x: 0, y: CGFloat(n)), end: CGPoint(x: 0, y: CGFloat(n) * 0.38), options: [.drawsAfterEndLocation])
        c.setFillColor(CGColor(red: 1, green: 0.86, blue: 0.55, alpha: 1))
        c.fillEllipse(in: CGRect(x: 130, y: 120, width: 140, height: 140))
        c.setFillColor(CGColor(red: 0.10, green: 0.07, blue: 0.20, alpha: 1))
        c.fill(CGRect(x: 0, y: 0, width: n, height: 150))
        c.setFillColor(CGColor(red: 0.98, green: 0.72, blue: 0.42, alpha: 0.9))
        c.move(to: CGPoint(x: 185, y: 150)); c.addLine(to: CGPoint(x: 215, y: 150))
        c.addLine(to: CGPoint(x: 320, y: 0)); c.addLine(to: CGPoint(x: 80, y: 0)); c.closePath(); c.fillPath()
        c.setFillColor(CGColor(red: 0.10, green: 0.07, blue: 0.20, alpha: 1))
        for i in 0..<5 {
            let y = CGFloat(130 - i * 32)
            c.fill(CGRect(x: 197 - CGFloat(i) * 2, y: y, width: 6 + CGFloat(i) * 4, height: 14 + CGFloat(i) * 2))
        }
        guard let img = c.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])
    }

    // MARK: Helpers

    /// Run-loop timer in common modes: keeps firing while a menu tracks (GCD's main queue
    /// doesn't), so a popped menu always closes on schedule.
    static func after(_ t: Double, _ f: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: max(0, t), repeats: false) { _ in MainActor.assumeIsolated { f() } }
        timer.tolerance = 0.002
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Moves the virtual pointer (eased) and lets the panel re-read it every step.
    static func move(to p: CGPoint, over d: Double, then: (@MainActor () -> Void)? = nil) {
        let s = CaptureState.shared
        let from = s.pointer ?? offPointer
        s.pointerVisible = true
        let steps = max(1, Int(d * 60))
        for i in 1...steps {
            after(Double(i) / 60) {
                let u = Double(i) / Double(steps)
                let e = u < 0.5 ? 2 * u * u : 1 - pow(-2 * u + 2, 2) / 2
                s.pointer = CGPoint(x: from.x + (p.x - from.x) * e, y: from.y + (p.y - from.y) * e)
                ctx.panel.captureResync()
                if i == steps { then?() }
            }
        }
    }

    static func press(_ action: @escaping @MainActor () -> Void) {
        CaptureState.shared.pointerDown = true
        after(0.12) {
            CaptureState.shared.pointerDown = false
            action()
        }
    }

    static func panelScreenPoint(_ r: CGRect, fx: CGFloat, fy: CGFloat) -> CGPoint {
        // r in hosting-view coordinates (top-left origin).
        let f = ctx.panel.frame
        return CGPoint(x: f.minX + r.minX + r.width * fx, y: f.maxY - (r.minY + r.height * fy))
    }

    /// Allow once: right half of the button row, which sits above "Answer in terminal".
    static func allowButtonPoint() -> CGPoint? {
        guard let r = ctx.panel.model.cardRect else { return nil }
        let f = ctx.panel.frame
        let bottom = f.maxY - r.maxY
        return CGPoint(x: f.minX + r.minX + r.width * 0.74, y: bottom + 12 + 24 + 6 + 14)
    }

    static func open(tab: TabID) {
        ctx.app.selectTab(tab)
        move(to: CGPoint(x: notch.midX + 12, y: top - 12), over: 0.5)
    }

    static func showBackdrop(_ path: String) {
        guard let img = NSImage(contentsOfFile: path) else { return }
        // Covers the compositor's notch canvas region (so Glass blurs the same backdrop).
        let s = ctx.screen.frame
        let region = CGRect(x: notch.midX - 480, y: s.maxY - 540, width: 960, height: 540)
        let w = NSWindow(contentRect: region, styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        w.ignoresMouseEvents = true
        w.isOpaque = true
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let v = NSImageView(frame: CGRect(origin: .zero, size: region.size))
        // The image is the compositor's notch-canvas backdrop (960 x 540 pt at 2x).
        let sub = img
        v.image = sub
        v.imageScaling = .scaleAxesIndependently
        w.contentView = v
        w.orderFrontRegardless()
        ctx.panel.orderFrontRegardless()
        backdropWindow = w
    }

    /// For glass stills: tells capture.py where to grab the real screen (the backdrop and the
    /// panel are on top there) and waits for it.
    static func requestScreenGrab(_ name: String, rect: CGRect, then: @escaping @MainActor () -> Void) {
        let s = ctx.screen.frame
        let r = rect.insetBy(dx: -24, dy: 0)
        let tl = [r.minX, s.maxY - r.maxY, r.width, min(r.height + 24, r.maxY - s.minY)].map { Double($0.rounded()) }
        // Foreign windows above the backdrop level inside the rect (would show in a screen grab).
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        let me = ProcessInfo.processInfo.processIdentifier
        let cg = CGRect(x: tl[0], y: tl[1], width: tl[2], height: tl[3])
        let foreign = list.filter { w in
            guard (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  let layer = w[kCGWindowLayer as String] as? Int, layer >= NSWindow.Level.mainMenu.rawValue + 2,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.01 else { return false }
            return CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!).intersects(cg)
        }.map { "\($0[kCGWindowOwnerName as String] ?? "?") layer \($0[kCGWindowLayer as String] ?? "?")" }
        let req: [String: Any] = ["name": name, "rect": tl, "foreign": foreign]
        let reqURL = outDir.appendingPathComponent("grab-\(name).json")
        let doneURL = outDir.appendingPathComponent("grab-\(name).done")
        if let d = try? JSONSerialization.data(withJSONObject: req) { try? d.write(to: reqURL) }
        func poll(_ n: Int) {
            if FileManager.default.fileExists(atPath: doneURL.path) || n > 100 { then(); return }
            after(0.1) { poll(n + 1) }
        }
        poll(0)
    }

    static func watchMenu() {
        menuObserver = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification,
                                                              object: nil, queue: .main) { n in
            nonisolated(unsafe) let m = n.object as? NSMenu
            MainActor.assumeIsolated { trackedMenu = m }
        }
    }

    static func closeMenu() { trackedMenu?.cancelTracking() }

    /// Scrolls the panel's alert list (the real NSScrollView) to `fraction` of its range.
    static func scrollAlerts(to fraction: CGFloat) {
        guard let sv = findScroll(in: ctx.panel.contentView) else { return }
        let docH = sv.documentView?.frame.height ?? 0
        let range = max(0, docH - sv.contentView.bounds.height)
        let flipped = sv.documentView?.isFlipped ?? true
        let y = flipped ? range * fraction : range * (1 - fraction)
        sv.contentView.scroll(to: CGPoint(x: 0, y: y))
        sv.reflectScrolledClipView(sv.contentView)
    }

    private static func findScroll(in v: NSView?) -> NSScrollView? {
        guard let v else { return nil }
        if let s = v as? NSScrollView, (s.documentView?.frame.height ?? 0) > s.contentView.bounds.height + 1 { return s }
        for sub in v.subviews { if let s = findScroll(in: sub) { return s } }
        return nil
    }

    static func animateScroll(from a: CGFloat, to b: CGFloat, over d: Double) {
        let steps = max(1, Int(d * 60))
        for i in 0...steps {
            after(Double(i) / 60) {
                let u = Double(i) / Double(steps)
                let e = u < 0.5 ? 2 * u * u : 1 - pow(-2 * u + 2, 2) / 2
                scrollAlerts(to: a + (b - a) * CGFloat(e))
            }
        }
    }

    static func swipe(left: Bool) {
        let dx: Double = left ? -7 : 7
        ctx.panel.captureSwipe(.began, dx: 0)
        for i in 1...10 { after(Double(i) * 0.018) { ctx.panel.captureSwipe(.changed, dx: dx) } }
        after(0.2) { ctx.panel.captureSwipe(.ended, dx: 0) }
    }

    static func showSettings(_ section: SettingsSection) {
        CaptureState.shared.settingsSection = section
        ctx.settings.show()
        placeSettings()
    }

    static func placeSettings() {
        let w = ctx.settings.captureWindow()
        w.setFrameOrigin(CGPoint(x: (notch.midX - w.frame.width / 2).rounded(), y: top - 112 - w.frame.height))
    }

    // MARK: Shots

    struct Script {
        var settle: Double = 0.8
        let duration: Double
        let setup: @MainActor () -> Void
        let steps: [(Double, @MainActor () -> Void)]
    }

    static let shots: [String: Script] = buildShots()

    private static func banner(_ b: Banner, action: (@MainActor () -> Void)? = nil) {
        ctx.app.offerBanner(b, action: action)
    }

    private static func buildShots() -> [String: Script] {
        var s: [String: Script] = [:]
        let restP: () -> CGPoint = { CGPoint(x: notch.midX + 150, y: top - 330) }

        s["closed-notch"] = Script(duration: 3, setup: {}, steps: [])

        s["hover-open-music"] = Script(duration: 5, setup: {
            CaptureState.shared.pointer = restP(); CaptureState.shared.pointerVisible = true
            ctx.app.selectTab(.music)
        }, steps: [
            (0.6, { move(to: CGPoint(x: notch.midX + 10, y: top - 14), over: 0.7) }),
        ])

        s["music-playing-loop"] = Script(duration: 5, setup: {
            ctx.app.selectTab(.music)
            CaptureState.shared.pointer = CGPoint(x: notch.midX + 10, y: top - 14)
            ctx.panel.captureResync()
        }, steps: [])

        s["approval-dwell-allow"] = Script(duration: 9.5, setup: {
            ctx.app.selectTab(.music)
            CaptureState.shared.pointer = restP(); CaptureState.shared.pointerVisible = true
        }, steps: [
            (0.6, { requestApproval() }),
            (2.2, {
                guard let p = allowButtonPoint() else { return }
                move(to: CGPoint(x: p.x - 40, y: p.y + 30), over: 0.45) {
                    move(to: p, over: 0.35)
                }
            }),
            (4.4, {
                guard let id = pendingApproval else { return }
                press { ctx.app.decide(id, .allow) }
            }),
            (6.4, { move(to: restP(), over: 0.6) }),
        ])

        s["approval-card-still"] = Script(duration: 2.5, setup: {
            ctx.app.selectTab(.music)
            requestApproval()
        }, steps: [])

        s["banner-claude-finished"] = Script(duration: 5, setup: {}, steps: [
            (0.5, {
                if let b = claudeFinishedBanner(sessionId: "demo-api", label: "api-server", worked: 4 * 60 + 12,
                                                enabled: true, now: Date()) { banner(b) }
            }),
        ])

        s["claude-sessions"] = Script(duration: 3, setup: {
            ctx.app.selectTab(.claude)
            CaptureState.shared.pointer = CGPoint(x: notch.midX + 10, y: top - 14)
            ctx.panel.captureResync()
        }, steps: [])

        s["banner-meeting"] = Script(duration: 5, setup: {}, steps: [
            (0.5, {
                let now = Date()
                ctx.app.captureMeetingReminder(MeetingInfo(
                    id: "demo-remind", title: "Design review", start: now.addingTimeInterval(60),
                    end: now.addingTimeInterval(31 * 60), allDay: false, calendarColorHex: "#3B82F6",
                    joinURL: URL(string: "https://teams.microsoft.com/l/meetup-join/demo"),
                    attendees: ["Priya S", "Rahul M"], calendarTitle: "Work"))
            }),
        ])

        s["calendar-hero"] = Script(duration: 5, setup: {
            CaptureState.shared.pointer = restP(); CaptureState.shared.pointerVisible = true
            ctx.app.selectTab(.calendar)
        }, steps: [
            (0.5, { move(to: CGPoint(x: notch.midX - 20, y: top - 14), over: 0.6) }),
        ])

        s["banner-teams"] = Script(duration: 5, setup: {}, steps: [
            (0.5, {
                ctx.app.captureAddAlert(AlertItem(id: "demo-new", app: teams, title: "Rahul M",
                                                  body: "Can you review the API PR before standup?", at: Date(), device: false))
                banner(Banner(id: "alert:demo-teams", kind: .alert(app: teams), title: "Rahul M",
                              subtitle: "Can you review the API PR before standup?", tab: .alerts))
            }),
        ])

        s["banner-outlook"] = Script(duration: 5, setup: {}, steps: [
            (0.5, {
                banner(Banner(id: "alert:demo-outlook", kind: .alert(app: outlook), title: "Priya S",
                              subtitle: "Re: Q4 roadmap, notes attached", tab: .alerts))
            }),
        ])

        s["alerts-scroll"] = Script(duration: 8, setup: {
            CaptureState.shared.pointer = restP(); CaptureState.shared.pointerVisible = true
            ctx.app.selectTab(.alerts)
        }, steps: [
            (0.4, { move(to: CGPoint(x: notch.midX + 30, y: top - 14), over: 0.6) }),
            (1.4, { move(to: CGPoint(x: notch.midX + 60, y: top - 150), over: 0.5) }),
            (2.6, { animateScroll(from: 0, to: 1, over: 1.6) }),
            (5.4, { animateScroll(from: 1, to: 0, over: 1.2) }),
        ])

        s["alerts-focus-moon"] = Script(duration: 2.5, setup: {
            ctx.app.quiet.captureSetFocus(true)
            ctx.app.selectTab(.alerts)
            CaptureState.shared.pointer = CGPoint(x: notch.midX + 10, y: top - 14)
            ctx.panel.captureResync()
        }, steps: [])

        s["music-seek-shuffle"] = Script(duration: 9, setup: {
            ctx.app.selectTab(.music)
            CaptureState.shared.pointer = CGPoint(x: notch.midX + 10, y: top - 14)
            CaptureState.shared.pointerVisible = true
            ctx.panel.captureResync()
        }, steps: [
            (0.8, { seekDemo() }),
        ])

        s["volume-popup"] = Script(duration: 4, setup: {}, steps: levelPresses(.volume, from: 0.5))
        s["brightness-popup"] = Script(duration: 4, setup: {}, steps: levelPresses(.brightness, from: 0.4375))

        s["banner-airpods"] = Script(duration: 5, setup: {}, steps: [
            (0.5, { ctx.app.onDeviceEvent(.bluetooth(name: "AirPods Pro", connected: true, battery: nil,
                                                     left: 82, right: 79, case: 64)) }),
        ])
        s["banner-charger"] = Script(duration: 5, setup: {}, steps: [
            (0.5, { ctx.app.onDeviceEvent(.power(charging: true, percent: 64, minutesToFullOrEmpty: 48)) }),
        ])
        s["banner-drive-eject"] = Script(duration: 8.5, setup: {
            CaptureState.shared.pointer = restP(); CaptureState.shared.pointerVisible = true
            ctx.panel.captureResync()
        }, steps: [
            (0.5, {
                ctx.app.onDeviceEvent(.drive(name: "DEMO-USB", mounted: true, freeBytes: 12_400_000_000, ejected: false)) {
                    ctx.app.onDeviceEvent(.drive(name: "DEMO-USB", mounted: false, freeBytes: nil, ejected: true))
                }
            }),
            (1.4, {
                guard let r = ctx.panel.model.bannerActionRect else { return }
                move(to: panelScreenPoint(r, fx: 0.5, fy: 0.5), over: 0.7)
            }),
            (2.9, { press { ctx.panel.model.onBannerAction?() } }),
            (4.2, { move(to: restP(), over: 0.6) }),
        ])

        s["swipe-tabs"] = Script(duration: 7, setup: {
            ctx.app.selectTab(.music)
            CaptureState.shared.pointer = CGPoint(x: notch.midX + 10, y: top - 14)
            CaptureState.shared.pointerVisible = true
            ctx.panel.captureResync()
        }, steps: [
            (0.3, { move(to: CGPoint(x: notch.midX + 40, y: top - 70), over: 0.5) }),
            (1.0, { swipe(left: true) }),
            (3.0, { swipe(left: true) }),
            (5.0, { swipe(left: true) }),
        ])

        s["context-menu"] = Script(duration: 4, setup: {
            watchMenu()
            CaptureState.shared.pointer = CGPoint(x: notch.midX + 30, y: top - 330)
        }, steps: [
            (0.4, {
                // The real menu, popped where a right-click on the closed notch shows it.
                // No event is posted: the event object only carries the location.
                CaptureState.shared.pointerVisible = false
                guard let host = ctx.panel.contentView,
                      let e = NSEvent.mouseEvent(with: .rightMouseDown,
                                                 location: CGPoint(x: host.bounds.midX, y: 2),
                                                 modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: ctx.panel.windowNumber, context: nil,
                                                 eventNumber: 0, clickCount: 1, pressure: 1) else { return }
                ctx.statusMenu.popUp(with: e, in: host)
            }),
            (3.2, { closeMenu() }),
        ])

        s["glass-music"] = glassScript(tab: .music)
        s["glass-alerts"] = glassScript(tab: .alerts)
        s["glass-calendar"] = glassScript(tab: .calendar)
        s["black-music-still"] = Script(duration: 1.5, setup: {
            ctx.app.selectTab(.music)
            CaptureState.shared.pointer = CGPoint(x: notch.midX + 10, y: top - 14)
            ctx.panel.captureResync()
        }, steps: [])

        // Settings (desk preset).
        for (name, section) in [("settings-general", SettingsSection.general), ("settings-notch", .notch),
                                ("settings-tabs", .tabs), ("settings-alerts", .alerts),
                                ("settings-calendar", .calendar), ("settings-appearance", .appearance),
                                ("settings-about", .about)] {
            s[name] = Script(settle: 1.0, duration: 2.5, setup: { showSettings(section) }, steps: [])
        }
        s["settings-sidebar-pan"] = Script(settle: 1.0, duration: 7.5, setup: { showSettings(.general) }, steps:
            SettingsSection.allCases.enumerated().map { i, sec in
                (0.4 + Double(i) * 1.0, { CaptureState.shared.settingsSection = sec })
            })
        s["settings-theme-glass"] = Script(settle: 1.0, duration: 5, setup: { showSettings(.appearance) }, steps: [
            (1.5, { ctx.app.settings.update { $0.theme = .glass } }),
        ])
        s["settings-open-from"] = Script(settle: 1.0, duration: 6, setup: { showSettings(.notch) }, steps: [
            (1.2, { ctx.app.settings.update { $0.openFrom = .left } }),
            (2.6, { ctx.app.settings.update { $0.animation = .smooth } }),
            (4.0, { ctx.app.settings.update { $0.openFrom = .centre; $0.animation = .spring } }),
        ])
        s["settings-turnoff-sheet"] = Script(settle: 1.0, duration: 5, setup: { showSettings(.general) }, steps: [
            (0.8, { NotchActions.removeClaudeHooks(settings: ctx.app.settings) { _ in } }),
            (3.8, {
                let w = ctx.settings.captureWindow()
                if let sheet = w.attachedSheet { w.endSheet(sheet, returnCode: .alertSecondButtonReturn) }
            }),
        ])

        // Welcome (desk preset).
        s["welcome-1-hover"] = Script(settle: 0.3, duration: 6, setup: { ctx.welcome.show(step: .hover) }, steps: [])
        s["welcome-2-permissions"] = Script(settle: 0.8, duration: 6, setup: {
            ctx.welcome.show(step: .permissions)
        }, steps: [
            (3.0, {
                CaptureState.shared.permissions[.calendar] = .granted
                ctx.welcome.permissions.refresh()
            }),
        ])
        s["welcome-3-tabs"] = Script(settle: 0.8, duration: 6.5, setup: {
            CaptureState.shared.permissions = [.calendar: .granted, .accessibility: .granted]
            ctx.welcome.show(step: .tabs)
        }, steps: [
            (1.6, { ctx.app.settings.update { $0.menuBarIcon = true } }),
            (4.4, { ctx.welcome.captureWindow?.performClose(nil) }),
        ])
        s["welcome-steps"] = Script(settle: 0.3, duration: 9, setup: { ctx.welcome.show(step: .hover) }, steps: [
            (3.0, { ctx.welcome.captureGo(.permissions) }),
            (6.0, { ctx.welcome.captureGo(.tabs) }),
        ])
        return s
    }

    private static func glassScript(tab: TabID) -> Script {
        Script(settle: 1.2, duration: 3, setup: {
            ctx.app.settings.update { $0.theme = .glass }
            ctx.app.selectTab(tab)
            CaptureState.shared.pointer = CGPoint(x: notch.midX + 10, y: top - 14)
            ctx.panel.captureResync()
        }, steps: [
            (0.6, {
                requestScreenGrab("glass-\(tab.rawValue)", rect: ctx.panel.frame) {}
            }),
        ])
    }

    private static func levelPresses(_ kind: HUDState.Kind, from start: Float) -> [(Double, @MainActor () -> Void)] {
        (0..<5).map { i in
            (0.5 + Double(i) * 0.16, {
                ctx.app.hud.show(kind, level: start + Float(i + 1) / 16, muted: false, now: Date())
            })
        }
    }

    private static func seekDemo() {
        let s = CaptureState.shared
        guard let r = s.scrubberRect else { return }
        let duration = 214.0
        let startFrac = (ctx.app.nowPlaying.state.info.flatMap { elapsedNow($0, now: Date()) } ?? 71) / duration
        let startP = panelScreenPoint(r, fx: startFrac, fy: 0.5)
        move(to: startP, over: 0.6) {
            s.scrubHover = true
            after(0.4) {
                s.pointerDown = true
                s.scrub = startFrac
                let target = 0.72
                let steps = 66
                for i in 1...steps {
                    after(Double(i) / 60) {
                        let u = Double(i) / Double(steps)
                        let e = u < 0.5 ? 2 * u * u : 1 - pow(-2 * u + 2, 2) / 2
                        let f = startFrac + (target - startFrac) * e
                        s.scrub = f
                        s.pointer = panelScreenPoint(r, fx: f, fy: 0.5)
                        if i == steps {
                            after(0.15) {
                                s.pointerDown = false
                                s.scrub = nil
                                ctx.app.nowPlaying.seek(to: target * duration)
                                after(0.5) {
                                    s.scrubHover = false
                                    shuffleThenOutput()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Shuffle sits left of the controls row, the output button right; both 32 pt, below the bar.
    private static func shuffleThenOutput() {
        guard let r = CaptureState.shared.scrubberRect else { return }
        let f = ctx.panel.frame
        // The controls row is centred under the bar row; 16 pt spacing, 32/18/44/18/32 buttons.
        let rowWidth: CGFloat = 32 + 32 + 44 + 32 + 32 + 4 * 16
        let midX = f.minX + r.midX - (r.minX - 0) * 0 // bar is centred in the row with the clocks
        let barMidY = f.maxY - r.midY
        let rowY = barMidY - 9 - 8 - 22
        let left = (f.minX + f.width / 2) - rowWidth / 2
        _ = midX
        let shuffle = CGPoint(x: left + 16, y: rowY)
        let output = CGPoint(x: left + rowWidth - 16, y: rowY)
        move(to: shuffle, over: 0.6) {
            after(0.3) {
                press { ctx.app.nowPlaying.send(.toggleShuffle) }
                after(1.0) { move(to: output, over: 0.7) }
            }
        }
    }
}
#endif
