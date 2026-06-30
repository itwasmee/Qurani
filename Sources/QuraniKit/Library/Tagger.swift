import Foundation

/// Heuristic guesser that turns a local file's name / folder / embedded tags into a
/// best-effort `(reciter, surah)` pair plus a confidence score. Pure logic, no I/O.
public enum Tagger {
    public struct Guess: Equatable, Sendable {
        public var reciterName: String?
        public var surahNumber: Int?
        public var confidence: Double

        public init(reciterName: String?, surahNumber: Int?, confidence: Double) {
            self.reciterName = reciterName
            self.surahNumber = surahNumber
            self.confidence = confidence
        }
    }

    // Folder names that carry no reciter signal (case-insensitive).
    private static let genericFolders: Set<String> = ["", "audio", "quran", "downloads", "music", "desktop"]
    // Trailing extensions we strip before parsing.
    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "aac", "ogg", "opus", "flac", "wav", "wma", "mp4", "caf", "aif", "aiff",
    ]
    // Token delimiters used when hunting for a standalone surah-number token.
    private static let tokenSeparators = CharacterSet(charactersIn: " -_.()[]")
    // Delimiters used to split a "reciter - title" style name.
    private static let reciterSeparators = CharacterSet(charactersIn: "-_")

    public static func guess(filename rawFilename: String, folder: String?, tags: [String: String], surahs: [Surah]) -> Guess {
        let filename = stripExtension(rawFilename.trimmingCharacters(in: .whitespacesAndNewlines))

        // ---- Surah number --------------------------------------------------
        // 0 = none, 1 = matched by name, 2 = explicit numeric token.
        var surahNumber: Int?
        var surahStrength = 0
        var numberToken: String?

        if let (n, tok) = numericSurahToken(in: filename) {
            surahNumber = n
            numberToken = tok
            surahStrength = 2
        } else if let n = nameMatchedSurah(in: filename, surahs: surahs) {
            surahNumber = n
            surahStrength = 1
        }

        // ---- Reciter -------------------------------------------------------
        // 0 = nil, 1 = guessed from a filename/title split, 2 = folder or tag.
        var reciterName: String?
        var reciterStrength = 0

        if let folder = folder?.trimmingCharacters(in: .whitespacesAndNewlines),
           !genericFolders.contains(folder.lowercased()) {
            reciterName = folder
            reciterStrength = 2
        }

        if reciterName == nil, let prefix = reciterPrefix(from: filename, numberToken: numberToken) {
            reciterName = prefix
            reciterStrength = 1
        }

        if reciterName == nil {
            if let artist = nonEmptyTag(tags["artist"]) {
                reciterName = artist
                reciterStrength = 2
            } else if let album = nonEmptyTag(tags["album"]) {
                reciterName = album
                reciterStrength = 2
            } else if let title = nonEmptyTag(tags["title"]),
                      let derived = reciterPrefix(from: title, numberToken: numberToken) {
                // A bare title is more likely the surah than the reciter, so we only
                // accept a "reciter - title" style split, never the whole title.
                reciterName = derived
                reciterStrength = 1
            }
        }

        return Guess(
            reciterName: reciterName,
            surahNumber: surahNumber,
            confidence: confidence(surahStrength: surahStrength, reciterStrength: reciterStrength)
        )
    }

    // MARK: - Filename helpers

    /// Strips a trailing `.<ext>` only when `<ext>` is a known audio extension, so a dot
    /// inside a name (e.g. `2.Al-Baqarah`) is left intact.
    private static func stripExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        let ext = name[name.index(after: dot)...].lowercased()
        return audioExtensions.contains(ext) ? String(name[..<dot]) : name
    }

    // MARK: - Surah helpers

    /// First standalone run of 1–3 ASCII digits whose value is in 1...114. A digit run
    /// glued to letters (the `12` in `track12`) is NOT a standalone token and is ignored.
    private static func numericSurahToken(in filename: String) -> (Int, String)? {
        for tok in filename.components(separatedBy: tokenSeparators) where !tok.isEmpty {
            guard tok.count <= 3, tok.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let n = Int(tok), (1...114).contains(n) else { continue }
            return (n, tok)
        }
        return nil
    }

    /// Matches a surah by transliteration substring or tashkeel-stripped Arabic name.
    private static func nameMatchedSurah(in filename: String, surahs: [Surah]) -> Int? {
        let lowerHay = filename.lowercased()
        let bareHay = ICYMetadata.stripTashkeel(filename)
        for s in surahs {
            if !s.translit.isEmpty, lowerHay.contains(s.translit.lowercased()) { return s.number }
            let bareName = ICYMetadata.stripTashkeel(s.nameAr)
            if !bareName.isEmpty, bareHay.contains(bareName) { return s.number }
        }
        return nil
    }

    // MARK: - Reciter helpers

    /// The portion before the first `-`/`_`, trimmed; nil when there is no separator or the
    /// portion is empty / a pure number / the surah-number token itself.
    private static func reciterPrefix(from text: String, numberToken: String?) -> String? {
        guard let sep = text.rangeOfCharacter(from: reciterSeparators) else { return nil }
        let prefix = String(text[..<sep.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty else { return nil }
        if prefix == numberToken { return nil }
        if prefix.allSatisfy({ $0.isASCII && $0.isNumber }) { return nil }
        return prefix
    }

    private static func nonEmptyTag(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    // MARK: - Confidence

    /// High (0.9) when both sides are hard signals (explicit number + folder/tag reciter);
    /// medium (0.5–0.65) when exactly one side is a heuristic guess; ≤0.4 when the reciter is
    /// unknown or nothing is solid.
    private static func confidence(surahStrength s: Int, reciterStrength r: Int) -> Double {
        switch (s, r) {
        case (2, 2): return 0.9
        case (2, 1): return 0.65
        case (1, 2): return 0.6
        case (0, 2): return 0.5
        case (1, 1): return 0.5
        case (0, 1): return 0.4
        default: // reciter nil (r == 0)
            return s > 0 ? 0.3 : 0.1
        }
    }
}
