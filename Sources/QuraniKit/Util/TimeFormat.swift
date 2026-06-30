import Foundation

/// Clock formatting for playback position / duration labels (the now-playing scrubber).
///
/// Under an hour it reads `m:ss` (e.g. 92 → "1:32"); at or past an hour it promotes to `h:mm:ss`
/// (e.g. 3725 → "1:02:05") so a long recitation like Al-Baqarah shows "1:32:05" rather than the
/// ambiguous "92:05". Non-finite or negative input clamps to "0:00". Pure + side-effect-free so it
/// can be unit-tested directly (see `TimeFormatTests`).
public enum TimeFormat {
    public static func label(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
