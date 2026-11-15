import Foundation
import NotchyCore

func runNowPlayingChecks() {
    func info(_ l: AdapterLine) -> NowPlayingInfo? { if case .data(let i) = l { return i }; return nil }
    func isData(_ l: AdapterLine) -> Bool { if case .data = l { return true }; return false }
    func isIgnored(_ l: AdapterLine) -> Bool { if case .ignored = l { return true }; return false }

    let e = parseAdapterLine(#"{"type":"data","diff":false,"payload":{}}"#[...])
    check("adapter.emptyPayload", isData(e) && info(e) == nil)

    let art = Data([1, 2, 3]).base64EncodedString()
    let f = info(parseAdapterLine(
        #"{"type":"data","diff":false,"payload":{"title":"T","artist":"A","playbackRate":1,"bundleIdentifier":"x.y","artworkData":"\#(art)"}}"#[...]))
    check("adapter.full", f?.title == "T" && f?.artist == "A" && f?.isPlaying == true
          && f?.artwork?.count == 3 && f?.bundleId == "x.y")

    let p = info(parseAdapterLine(
        #"{"type":"data","payload":{"title":"T","artist":"A","playbackRate":0}}"#[...]))
    check("adapter.paused", p != nil && p?.isPlaying == false)

    let b = info(parseAdapterLine(
        #"{"type":"data","payload":{"title":"T","artist":"A","playbackRate":1,"artworkData":"%%%"}}"#[...]))
    check("adapter.badArt", b?.title == "T" && b?.artwork == nil)

    // Escaped slashes in base64 must decode.
    let slash = info(parseAdapterLine(
        #"{"type":"data","payload":{"title":"T","artworkData":"\/9j\/"}}"#[...]))
    check("adapter.escapedSlash", slash?.artwork == Data([0xff, 0xd8, 0xff]))

    let big = Data(count: 2 * 1024 * 1024 + 1).base64EncodedString()
    let bi = info(parseAdapterLine(
        #"{"type":"data","payload":{"title":"T","artworkData":"\#(big)"}}"#[...]))
    check("adapter.bigArt", bi?.title == "T" && bi?.artwork == nil)

    check("adapter.garbage",
          ["not json", "{", #"{"type":"error"}"#, "", #"{"type":"data"}"#]
              .allSatisfy { isIgnored(parseAdapterLine($0[...])) })

    let t0 = Date(timeIntervalSince1970: 1_000_000)
    var s = NowPlayingState()
    s.apply(NowPlayingInfo(title: "T", artist: "A", isPlaying: true), now: t0)
    check("state.playingVisible", s.visible(now: t0 + 1))
    s.apply(NowPlayingInfo(title: "T", artist: "A", isPlaying: false), now: t0 + 5)
    check("state.pausedVisibleFor10Min", s.visible(now: t0 + 605) && !s.visible(now: t0 + 606))

    var n = NowPlayingState()
    n.apply(nil, now: t0)
    check("state.nothingPlayingHidden", !n.visible(now: t0))
    var np = NowPlayingState()
    np.apply(NowPlayingInfo(title: "T", artist: "A", isPlaying: false), now: t0)
    check("state.pausedNeverPlayedHidden", !np.visible(now: t0))
    s.apply(nil, now: t0 + 10)
    check("state.nilClears", s.info == nil && !s.visible(now: t0 + 10))

    var r = RestartPolicy()
    let seq = [r.nextDelay(), r.nextDelay(), r.nextDelay(), r.nextDelay()]
    check("restart.backoff", seq == [1, 5, 30, nil])
    r.reset()
    check("restart.reset", r.nextDelay() == 1)

    let script = "/Applications/Notchy.app/Contents/Resources/mediaremote-adapter/mediaremote-adapter.pl"
    let fw = "/Applications/Notchy.app/Contents/Resources/mediaremote-adapter/MediaRemoteAdapter.framework"
    let ps = """
      104     1 /System/Library/PrivateFrameworks/MediaRemote.framework/Support/mediaremoted
    78749     1 /usr/bin/perl \(script) \(fw) stream --no-diff --debounce=100
    78750 78747 /usr/bin/perl \(script) \(fw) stream --no-diff --debounce=100
    78751     1 /usr/bin/perl \(script) \(fw) send 2
    80006     1 /usr/bin/perl /Applications/Wispr Flow.app/Contents/Resources/run.pl /x/MediaRemoteAdapter loop
    80007     1 /usr/bin/perl /Other/mediaremote-adapter.pl \(fw) stream
    80008     1 /usr/bin/perl \(script)x \(fw) stream
    garbage line
    """
    check("orphans.onlyOwnStreamWithLaunchdParent", orphanedAdapterPIDs(psOutput: ps, script: script) == [78749])
    check("orphans.emptyInput", orphanedAdapterPIDs(psOutput: "", script: script).isEmpty)

    // Progress (Task 4)
    let pj = info(parseAdapterLine(
        #"{"type":"data","payload":{"title":"T","artist":"A","playbackRate":1,"duration":200.5,"elapsedTime":10,"timestamp":"2026-11-14T17:36:36Z","shuffleMode":3}}"#[...]))
    check("np.durationParsed", pj?.duration == 200.5 && pj?.elapsed == 10 && pj?.elapsedAt != nil
          && pj?.shuffle == true)
    check("np.shuffleOff", info(parseAdapterLine(
        #"{"type":"data","payload":{"title":"T","shuffleMode":1}}"#[...]))?.shuffle == false)
    check("np.shuffleAbsent", p?.shuffle == nil)
    let adv = NowPlayingInfo(title: "T", artist: "A", isPlaying: true, duration: 200, elapsed: 10, elapsedAt: t0, rate: 1)
    check("np.elapsedAdvances", elapsedNow(adv, now: t0 + 5) == 15)
    var paused = adv; paused.isPlaying = false; paused.rate = 0
    check("np.elapsedPausedFrozen", elapsedNow(paused, now: t0 + 50) == 10)
    check("np.elapsedClamped", elapsedNow(adv, now: t0 + 9999) == 200)
    check("seek.mid", seekPosition(fraction: 0.5, duration: 200) == 100)
    check("seek.clamp", seekPosition(fraction: -0.2, duration: 200) == 0 && seekPosition(fraction: 1.4, duration: 200) == 200)
    check("seek.noDuration", seekPosition(fraction: 0.5, duration: nil) == nil)
    check("scrub.fraction", scrubFraction(x: 75, width: 300) == 0.25 && scrubFraction(x: -5, width: 300) == 0
          && scrubFraction(x: 400, width: 300) == 1)
    var st = NowPlayingState(); st.apply(adv, now: t0)
    st.applySeek(to: 120, now: t0 + 3)
    check("seek.applyLocal", st.info.flatMap { elapsedNow($0, now: t0 + 3) } == 120
          && st.info.flatMap { elapsedNow($0, now: t0 + 5) } == 122)
    var none = NowPlayingState(); none.applySeek(to: 50, now: t0)
    check("seek.nilNoop", none.info == nil)
    var pst = NowPlayingState(); pst.apply(paused, now: t0); pst.applySeek(to: 60, now: t0 + 1)
    check("seek.pausedFrozen", pst.info.flatMap { elapsedNow($0, now: t0 + 90) } == 60)
    var g = NowPlayingState(); g.apply(adv, now: t0); g.applySeek(to: 120, now: t0 + 1)
    var stale = adv; stale.elapsed = 12; stale.elapsedAt = t0 + 1.2
    g.apply(stale, now: t0 + 1.2)
    check("seek.guardStale", g.info?.elapsed == 120)
    var near = adv; near.elapsed = 121; near.elapsedAt = t0 + 1.3
    g.apply(near, now: t0 + 1.3)
    check("seek.guardNearAccepted", g.info?.elapsed == 121)
    g.apply(stale, now: t0 + 1.4)
    check("seek.guardEndsOnConfirm", g.info?.elapsed == 12)
    var g2 = NowPlayingState(); g2.apply(adv, now: t0); g2.applySeek(to: 120, now: t0 + 1)
    g2.apply(stale, now: t0 + 3)
    check("seek.guardExpires", g2.info?.elapsed == 12)
    let bad = info(parseAdapterLine(
        #"{"type":"data","payload":{"title":"T","playbackRate":1,"duration":100,"elapsedTime":42,"timestamp":"nope"}}"#[...]))
    check("np.timestampBad", bad?.elapsedAt == nil && bad.flatMap { elapsedNow($0, now: t0) } == 42)
}
