import Testing
import Foundation
@testable import QuraniKit

/// A live-station fixture for the reconnect seam tests.
private func liveStation(_ id: String = "makkah") -> Station {
    Station(id: id, name: "Makkah — Al-Haram", region: "Makkah", kind: .icecast,
            url: URL(string: "https://example.com/\(id).mp3")!, reciter: nil, hasVideo: false)
}

/// Builds an engine whose reconnect backoff resolves instantly, so tests exercise the retry
/// sequencing without waiting the real 1s/2s/4s.
@MainActor private func fastEngine(_ p: FakePlayer,
                                   maxAttempts: Int = 3) -> PlaybackEngine {
    PlaybackEngine(player: p, reconnect: LiveReconnectPolicy(maxAttempts: maxAttempts),
                   backoffSleep: { _ in })
}

// MARK: - Pure policy

@Test func policyReconnectsOnlyLiveWithBudgetLeft() {
    let p = LiveReconnectPolicy(maxAttempts: 3)
    #expect(p.shouldReconnect(sourceID: "live:makkah", attemptsUsed: 0))
    #expect(p.shouldReconnect(sourceID: "live:makkah", attemptsUsed: 2))
    #expect(!p.shouldReconnect(sourceID: "live:makkah", attemptsUsed: 3))   // budget spent
    #expect(!p.shouldReconnect(sourceID: "ondemand:9:3:67", attemptsUsed: 0)) // finite item
    #expect(!p.shouldReconnect(sourceID: "local:abc", attemptsUsed: 0))
    #expect(!p.shouldReconnect(sourceID: nil, attemptsUsed: 0))
}

@Test func policyBackoffIsExponential() {
    let p = LiveReconnectPolicy()
    #expect(p.backoff(forAttempt: 1) == .seconds(1))
    #expect(p.backoff(forAttempt: 2) == .seconds(2))
    #expect(p.backoff(forAttempt: 3) == .seconds(4))
}

// MARK: - Engine wiring

@MainActor @Test func liveFailureEntersReconnectingNotFailed() {
    let p = FakePlayer(); let e = fastEngine(p)
    e.playStation(liveStation())
    p.onFailure?("drop")
    #expect(e.status == .reconnecting)               // silent retry, not the failure bar
    #expect(e.reconnectAttemptsForTesting == 1)
    if case .failed = e.status { Issue.record("live drop must not surface .failed on the first attempt") }
}

@MainActor @Test func liveReconnectRecoversAndResetsCounter() async {
    let p = FakePlayer(); let e = fastEngine(p)
    e.playStation(liveStation())                     // autoConfirm → .playing, attempts 0
    p.onFailure?("drop")                             // → .reconnecting, attempt 1
    await e.reconnectTaskForTesting?.value           // backoff (instant) + re-issue → autoConfirm .playing
    #expect(e.status == .playing)                    // recovered
    #expect(e.reconnectAttemptsForTesting == 0)      // counter reset on resume
    #expect(p.playCount == 2)                        // original + one reconnect re-issue
    #expect(p.lastURL == liveStation().url)          // same live URL rebuilt
}

@MainActor @Test func liveReconnectGivesUpAfterThreeAttempts() async {
    let p = FakePlayer(); p.autoConfirm = false      // re-issued play() never confirms → drops persist
    let e = fastEngine(p)
    e.playStation(liveStation())
    p.onStatus?(true)                                // simulate the initial connect
    for expected in 1...3 {                          // three silent reconnects
        p.onFailure?("drop")
        #expect(e.status == .reconnecting)
        #expect(e.reconnectAttemptsForTesting == expected)
        await e.reconnectTaskForTesting?.value       // re-issues the stream
    }
    #expect(p.playCount == 4)                        // initial + 3 reconnect re-issues
    p.onFailure?("drop")                             // 4th failure — budget spent
    #expect(e.status == .failed("drop"))             // now the retry bar
    #expect(p.playCount == 4)                        // no further re-issue
}

@MainActor @Test func stopCancelsPendingReconnect() async {
    let p = FakePlayer(); p.autoConfirm = false
    let e = fastEngine(p)
    e.playStation(liveStation())
    p.onStatus?(true)
    p.onFailure?("drop")                             // schedule a reconnect
    let pending = e.reconnectTaskForTesting          // capture before stop() clears it
    e.stop()
    await pending?.value                             // let the cancelled task settle
    #expect(e.status == .idle)
    #expect(e.currentSourceID == nil)
    #expect(p.playCount == 1)                        // reconnect never re-issued
    #expect(e.reconnectAttemptsForTesting == 0)
}

@MainActor @Test func switchingStationCancelsOldReconnect() async {
    let p = FakePlayer(); p.autoConfirm = false
    let e = fastEngine(p)
    e.playStation(liveStation("a"))
    p.onStatus?(true)
    p.onFailure?("drop")                             // schedule reconnect for station a
    let pending = e.reconnectTaskForTesting
    e.playStation(liveStation("b"))                  // switch supersedes it
    await pending?.value                             // old task must no-op (identity guard)
    #expect(e.currentSourceID == "live:b")
    #expect(e.reconnectAttemptsForTesting == 0)      // fresh budget for the new station
    #expect(p.lastURL == liveStation("b").url)       // never reloaded station a
}

@MainActor @Test func togglingDuringReconnectStopsRetrying() async {
    let p = FakePlayer(); p.autoConfirm = false
    let e = fastEngine(p)
    e.playStation(liveStation())
    p.onStatus?(true)
    p.onFailure?("drop")                             // → .reconnecting
    let pending = e.reconnectTaskForTesting
    e.toggle()                                       // listener aborts the reconnect
    #expect(e.status == .paused)
    await pending?.value
    #expect(p.playCount == 1)                        // no reconnect re-issue
    #expect(e.reconnectAttemptsForTesting == 0)
}

@MainActor @Test func manualRetryResetsReconnectBudget() {
    let p = FakePlayer(); p.autoConfirm = false
    let e = fastEngine(p)
    e.playStation(liveStation())
    p.onStatus?(true)
    p.onFailure?("drop")                             // attempt 1
    #expect(e.reconnectAttemptsForTesting == 1)
    e.retry()                                        // manual "tap to retry" → fresh budget
    #expect(e.reconnectAttemptsForTesting == 0)
    #expect(e.reconnectTaskForTesting == nil)        // any pending reconnect cancelled
}
