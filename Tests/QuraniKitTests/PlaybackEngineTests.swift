import Testing
import Foundation
@testable import QuraniKit

@MainActor final class FakePlayer: AudioPlayer {
    var onStatus: ((Bool) -> Void)?
    var onStreamTitle: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    var volume: Float = 1.0
    /// When false, `play()`/`pause()` do not auto-confirm, so `.loading` is observable
    /// until the test fires `onStatus` manually.
    var autoConfirm = true
    private(set) var lastURL: URL?
    private(set) var playCount = 0, pauseCount = 0
    func replace(url: URL) { lastURL = url }
    func play() { playCount += 1; if autoConfirm { onStatus?(true) } }
    func pause() { pauseCount += 1; if autoConfirm { onStatus?(false) } }
}

@MainActor @Test func playingStationSetsLoadingThenPlaying() {
    let p = FakePlayer(); let engine = PlaybackEngine(player: p)
    let st = Station(id: "x", name: "Makkah — Al-Haram", region: "Makkah", kind: .hls,
                     url: URL(string: "https://example.com/x.m3u8")!, reciter: nil, hasVideo: true)
    engine.play(st)
    #expect(p.lastURL?.absoluteString == "https://example.com/x.m3u8")
    #expect(engine.status == .playing)
    #expect(engine.nowPlaying?.title == "Makkah — Al-Haram")
    #expect(engine.nowPlaying?.isLive == true)
}

@MainActor @Test func togglePausesAndResumes() {
    let p = FakePlayer(); let engine = PlaybackEngine(player: p)
    engine.play(Station(id: "x", name: "n", region: "r", kind: .icecast,
                        url: URL(string: "https://e.com/a")!, reciter: "Ghamdi", hasVideo: false))
    engine.toggle(); #expect(engine.status == .paused)
    engine.toggle(); #expect(engine.status == .playing)
}

@MainActor @Test func playSetsLoadingBeforePlayerConfirms() {
    let p = FakePlayer(); p.autoConfirm = false   // don't jump straight to .playing
    let engine = PlaybackEngine(player: p)
    let st = Station(id: "x", name: "Makkah", region: "Makkah", kind: .hls,
                     url: URL(string: "https://e.com/x.m3u8")!, reciter: nil, hasVideo: true)
    engine.play(st)
    #expect(engine.status == .loading)             // observable: player hasn't confirmed yet
    #expect(engine.currentStationID == "x")
    p.onStatus?(true)
    #expect(engine.status == .playing)
}

@MainActor @Test func stopResetsStatusNowPlayingAndStation() {
    let p = FakePlayer(); let engine = PlaybackEngine(player: p)
    engine.play(Station(id: "x", name: "n", region: "r", kind: .icecast,
                        url: URL(string: "https://e.com/a")!, reciter: "G", hasVideo: false))
    #expect(engine.nowPlaying != nil)
    engine.stop()
    #expect(engine.status == .idle)
    #expect(engine.nowPlaying == nil)
    #expect(engine.currentStationID == nil)
    #expect(p.pauseCount == 1)
}

@MainActor @Test func volumePropagatesToPlayer() {
    let p = FakePlayer(); let engine = PlaybackEngine(player: p)
    engine.volume = 0.3
    #expect(p.volume == 0.3)
    engine.play(Station(id: "x", name: "n", region: "r", kind: .icecast,
                        url: URL(string: "https://e.com/a")!, reciter: nil, hasVideo: false))
    #expect(p.volume == 0.3)                       // play() re-applies the engine volume
}

@MainActor @Test func playerFailurePropagatesToFailedStatus() {
    let p = FakePlayer(); let engine = PlaybackEngine(player: p)
    engine.play(Station(id: "x", name: "Egypt", region: "Cairo", kind: .icecast,
                        url: URL(string: "https://e.com/dead")!, reciter: nil, hasVideo: false))
    p.onFailure?("boom")
    #expect(engine.status == .failed("boom"))
}

@MainActor @Test func streamTitleUpdatesSurahHint() {
    let p = FakePlayer(); let engine = PlaybackEngine(player: p)
    engine.attachSurahs([Surah(number: 67, nameAr: "الْمُلْك", translit: "Al-Mulk", nameEn: "", ayahCount: 30, makki: true, juz: 29)])
    engine.play(Station(id: "x", name: "n", region: "r", kind: .icecast,
                        url: URL(string: "https://e.com/a")!, reciter: "Sudais", hasVideo: false))
    p.onStreamTitle?("Sudais - Al-Mulk")
    #expect(engine.nowPlaying?.surahHint == "الْمُلْك")
}
