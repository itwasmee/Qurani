import Foundation

public enum ICYMetadata {
    /// Strips Arabic tashkeel (harakat) so bare-name comparisons match vowelized data.
    static func stripTashkeel(_ s: String) -> String {
        // The harakat set must be built over Unicode *scalars*, not Characters.
        // A string literal of bare combining marks collapses into a single grapheme
        // cluster, so `Set<Character>(...)` has count 1 and matches no individual mark —
        // the filter would strip nothing. Compare scalar-to-scalar instead.
        let harakat = Set("\u{064B}\u{064C}\u{064D}\u{064E}\u{064F}\u{0650}\u{0651}\u{0652}\u{0653}\u{0670}".unicodeScalars)
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: s.unicodeScalars.filter { !harakat.contains($0) })
        return String(scalars)
    }

    public static func surahHint(from streamTitle: String, surahs: [Surah]) -> String? {
        let hay = streamTitle.lowercased()
        let bareHay = stripTashkeel(streamTitle)
        for s in surahs {
            if hay.contains(s.translit.lowercased()) { return s.nameAr }
            if bareHay.contains(stripTashkeel(s.nameAr)) { return s.nameAr }
        }
        return nil
    }
}
