import Foundation

/// Autoplay ordering for on-demand recitation: given a moshaf's ordered surah list, the surah that
/// should play after the current one. Pure and isolated so it is unit-testable — the AppModel wiring
/// that consumes it lives in the App target, which has no unit-test bundle.
public enum Autoplay {
    /// The surah number after the first occurrence of `current` in `order`, or nil when `current`
    /// is the last element or is absent — the signal to stop autoplay.
    public static func nextSurah(in order: [Int], after current: Int) -> Int? {
        guard let i = order.firstIndex(of: current), i + 1 < order.count else { return nil }
        return order[i + 1]
    }
}
