import Foundation

/// Pure decision policy for silently reconnecting a dropped LIVE radio stream before surfacing a
/// hard failure. Live stations (Shoutcast/Icecast/Mixlr/HLS world feeds) drop or stall transiently;
/// rather than throwing the listener straight to the "tap to retry" bar, `PlaybackEngine` consults
/// this policy to retry a few times with exponential backoff. Kept free of AVPlayer/engine state so
/// the two questions — "should we reconnect?" and "how long do we wait?" — are unit-testable without
/// a network or a real player.
public struct LiveReconnectPolicy: Sendable, Equatable {
    /// Maximum silent reconnect attempts before the engine falls through to `.failed`.
    public let maxAttempts: Int

    public init(maxAttempts: Int = 3) {
        self.maxAttempts = max(0, maxAttempts)
    }

    /// Whether a failure/stall on `sourceID`, after `attemptsUsed` prior silent reconnects, warrants
    /// another attempt. Only LIVE sources reconnect — a finite on-demand/local item that stops is
    /// either finished or genuinely broken, never a transient live drop, so those always return
    /// `false`, leaving the existing `.failed` + retry-bar behavior untouched for non-live playback.
    public func shouldReconnect(sourceID: String?, attemptsUsed: Int) -> Bool {
        guard let sourceID, sourceID.hasPrefix("live:") else { return false }
        return attemptsUsed < maxAttempts
    }

    /// Backoff before the `attempt`-th reconnect (1-based): ~1s, 2s, 4s, … (2^(attempt-1) seconds),
    /// so successive drops back off exponentially instead of hammering a struggling server.
    public func backoff(forAttempt attempt: Int) -> Duration {
        let n = max(1, attempt)
        return .seconds(1 << (n - 1))
    }
}
