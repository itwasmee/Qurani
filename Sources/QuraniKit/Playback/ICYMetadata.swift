import Foundation

public enum ICYMetadata {
    // Built over Unicode *scalars*, not Characters: a string literal of bare combining
    // marks collapses into a single grapheme cluster, so `Set<Character>(...)` would have
    // count 1 and match no individual mark. Hoisted to a static so it's built once.
    private static let harakat = Set("\u{064B}\u{064C}\u{064D}\u{064E}\u{064F}\u{0650}\u{0651}\u{0652}\u{0653}\u{0670}".unicodeScalars)

    /// Strips Arabic tashkeel (harakat) so bare-name comparisons match vowelized data.
    static func stripTashkeel(_ s: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: s.unicodeScalars.filter { !Self.harakat.contains($0) })
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
