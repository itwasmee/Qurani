import Testing
import Foundation
@testable import QuraniKit

@MainActor final class FakePlayer: AudioPlayer {
    var onStatus: ((Bool) -> Void)?
    var onStreamTitle: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    var onTime: ((Double, Double) -> Void)?
    var onFinish: (() -> Void)?
    var volume: Float = 1.0
    /// When false, `play()`/`pause()` do not auto-confirm, so `.loading` is observable
    /// until the test fires `onStatus` manually.
    var autoConfirm = true
    private(set) var lastURL: URL?
    private(set) var playCount = 0, pauseCount = 0
    private(set) var lastSeekFraction: Double?
    func replace(url: URL) { lastURL = url }
    func play() { playCount += 1; if autoConfirm { onStatus?(true) } }
    func pause() { pauseCount += 1; if autoConfirm { onStatus?(false) } }
    func seek(toFraction f: Double) { lastSeekFraction = f }
}

/// Shared on-demand fixture for the seam tests.
let testSurah = Surah(number: 67, nameAr: "الْمُلْك", translit: "Al-Mulk", nameEn: "Al-Mulk",
                      ayahCount: 30, makki: true, juz: 29)

@MainActor @Test func playingStationSetsLoadingThenPlaying() {
    let p = FakePlayer(); let engine = PlaybackEngine(player: p)
    let st = Station(id: "x", name: "Makkah — Al-Haram", region: "Makkah", kind: .hls,
                     url: URL(string: "https://example.com/x.m3u8")!, reciter: nil, hasVideo: true)
    engine.playStation(st)
    #expect(p.lastURL?.absoluteString == "https://example.com/x.m3u8")
    #expect(engine.status == .playing)
    #expect(engine.nowPlaying?.title == "Makkah — Al-Haram")
    #expect(engine.nowPlaying?.isLive == true)
}

@MainActor @Test func togglePausesAndResumes() {
    let p = FakePlayer(); let engine = PlaybackEngine(player: p)
    engine.playStation(Station(id: "x", name: "n", region: "r", kind: .icecast,
                        url: URL(string: "https://e.com/a")!, reciter: "Ghamdi", hasVideo: false))
    engine.toggle(); #expect(engine.status == .paused)
    engine.toggle(); #expect(engine.status == .playing)
}

@MainActor @Test func playSetsLoadingBeforePlayerConfirms() {
    let p = FakePlayer(); p.autoConfirm = false   // don't jump straight to .playing
    let engine = PlaybackEngine(player: p)
    let st = Station(id: "x", name: "Makkah", region: "Makkah", kind: .hls,
                     url: URL(string: "https://e.com/x.m3u8")!, reciter: nil, hasVideo: true)
    engine.playStation(st)
    #expect(engine.status == .loading)             // observable: player hasn't confirmed yet
    #expect(engine.currentSourceID == "live:x")
    p.onStatus?(true)
    #expect(engine.status == .playing)
}

@MainActor @Test func stopResetsStatusNowPlayingAndStation() {
    let p = FakePlayer(); let engine = PlaybackEngine(player: p)
    engine.playStation(Station(id: "x", name: "n", region: "r", kind: .icecast,
                        url: URL(string: "https://e.com/a")!, reciter: "G", hasVideo: false))
    #expect(engine.nowPlaying != nil)
    engine.stop()
    #expect(engine.status == .idle)
    #expect(engine.nowPlaying == nil)
    #expect(engine.currentSourceID == nil)
    #expect(p.pauseCount == 1)
}

@MainActor @Test func volumePropagatesToPlayer() {
    let p = FakePlayer(); let engine = PlaybackEngine(player: p)
    engine.volume = 0.3
    #expect(p.volume == 0.3)
    engine.playStation(Station(id: "x", name: "n", region: "r", kind: .icecast,
                        url: URL(string: "https://e.com/a")!, reciter: nil, hasVideo: false))
    #expect(p.volume == 0.3)                       // play() re-applies the engine volume
}

@MainActor @Test func playerFailurePropagatesToFailedStatus() {
    let p = FakePlayer(); let engine = PlaybackEngine(player: p)
    engine.playStation(Station(id: "x", name: "Egypt", region: "Cairo", kind: .icecast,
                        url: URL(string: "https://e.com/dead")!, reciter: nil, hasVideo: false))
    p.onFailure?("boom")
    #expect(engine.status == .failed("boom"))
}

@MainActor @Test func lateFailureWhenIdleIsIgnored() {
    let p = FakePlayer(); let engine = PlaybackEngine(player: p)
    engine.playStation(Station(id: "x", name: "Egypt", region: "Cairo", kind: .icecast,
                        url: URL(string: "https://e.com/dead")!, reciter: nil, hasVideo: false))
    engine.stop()
    p.onFailure?("boom")                 // late failure after stop()/idle must be a no-op
    #expect(engine.status == .idle)      // NOT .failed("boom")
    #expect(engine.nowPlaying == nil)
}

@MainActor @Test func streamTitleUpdatesSurahHint() {
    let p = FakePlayer(); let engine = PlaybackEngine(player: p)
    engine.attachSurahs([Surah(number: 67, nameAr: "الْمُلْك", translit: "Al-Mulk", nameEn: "", ayahCount: 30, makki: true, juz: 29)])
    engine.playStation(Station(id: "x", name: "n", region: "r", kind: .icecast,
                        url: URL(string: "https://e.com/a")!, reciter: "Sudais", hasVideo: false))
    p.onStreamTitle?("Sudais - Al-Mulk")
    #expect(engine.nowPlaying?.surahHint == "الْمُلْك")
}

@MainActor @Test func playsOnDemandItem() {
    let p = FakePlayer(); let e = PlaybackEngine(player: p)
    let s = Surah(number: 67, nameAr: "الْمُلْك", translit: "Al-Mulk", nameEn: "", ayahCount: 30, makki: true, juz: 29)
    let url = URL(string: "https://server.example/067.mp3")!
    e.play(.onDemand(reciterName: "Sudais", surah: s, url: url))
    #expect(p.lastURL == url)
    #expect(e.nowPlaying?.title == "الْمُلْك")
    #expect(e.nowPlaying?.subtitle == "Sudais")
    #expect(e.nowPlaying?.isLive == false)
    #expect(e.currentSourceID == "ondemand:Sudais:67")
}

@MainActor @Test func stationStillPlaysViaConvenience() {
    let p = FakePlayer(); let e = PlaybackEngine(player: p)
    let st = Station(id: "x", name: "Makkah", region: "Makkah", kind: .hls, url: URL(string:"https://e/x.m3u8")!, reciter: nil, hasVideo: true)
    e.playStation(st)
    #expect(e.currentSourceID == "live:x")
    #expect(e.nowPlaying?.isLive == true)
}

@MainActor @Test func timeUpdatesPopulateNowPlaying() {
    let p = FakePlayer(); let e = PlaybackEngine(player: p)
    e.play(.onDemand(reciterName: "R", surah: testSurah, url: URL(string:"https://e/1.mp3")!))
    p.onTime?(12, 60)
    #expect(e.nowPlaying?.elapsed == 12); #expect(e.nowPlaying?.duration == 60)
}

@MainActor @Test func seekDelegatesFraction() {
    let p = FakePlayer(); let e = PlaybackEngine(player: p)
    e.play(.onDemand(reciterName: "R", surah: testSurah, url: URL(string:"https://e/1.mp3")!))
    e.seek(toFraction: 0.5); #expect(p.lastSeekFraction == 0.5)
}

@MainActor @Test func finishInvokesHook() {
    let p = FakePlayer(); let e = PlaybackEngine(player: p); var fired = false
    e.onFinish = { fired = true }
    e.play(.onDemand(reciterName: "R", surah: testSurah, url: URL(string:"https://e/1.mp3")!))
    p.onFinish?(); #expect(fired)
}
