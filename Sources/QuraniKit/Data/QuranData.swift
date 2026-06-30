import Foundation

public enum QuranData {
    public static func loadSurahs(bundle: Bundle) throws -> [Surah] {
        guard let url = bundle.url(forResource: "surahs", withExtension: "json") else {
            throw NSError(domain: "QuranData", code: 1, userInfo: [NSLocalizedDescriptionKey: "surahs.json missing"])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Surah].self, from: data).sorted { $0.number < $1.number }
    }
    // `.module` is generated as an internal accessor, so it cannot be a default
    // argument of a public method; supply it from inside the body via this overload.
    public static func loadSurahs() throws -> [Surah] {
        try loadSurahs(bundle: .module)
    }
    public static func surah(_ n: Int, in surahs: [Surah]) -> Surah? {
        surahs.first { $0.number == n }
    }
}
