import Foundation

/// Decodes the mp3quran v3 `/reciters` payload into our `Reciter`/`Moshaf` models and
/// builds per-surah audio URLs. Pure logic — no networking lives here.
public enum CatalogService {
    private struct Payload: Decodable { let reciters: [RawReciter] }
    private struct RawReciter: Decodable { let id: Int; let name: String; let moshaf: [RawMoshaf] }
    private struct RawMoshaf: Decodable { let id: Int; let name: String; let server: String; let surah_list: String }

    /// Upgrades an `http://` server URL to `https://` (rewriting only the scheme prefix),
    /// leaving any other scheme untouched. Returns nil if the result isn't a valid URL.
    static func upgrade(_ s: String) -> URL? {
        var str = s
        if str.hasPrefix("http://") { str = "https://" + str.dropFirst("http://".count) }
        return URL(string: str)
    }

    /// Decodes reciters, dropping moshafs whose server URL is unusable and reciters left
    /// with no usable moshaf. `surah_list` (comma-separated, tolerant of spaces) → `[Int]`.
    public static func decodeReciters(_ data: Data) throws -> [Reciter] {
        try JSONDecoder().decode(Payload.self, from: data).reciters.compactMap { r in
            let moshafs = r.moshaf.compactMap { m -> Moshaf? in
                guard let base = upgrade(m.server) else { return nil }
                let nums = m.surah_list.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                return Moshaf(id: m.id, name: m.name, serverBase: base, surahNumbers: nums)
            }
            return moshafs.isEmpty ? nil : Reciter(id: r.id, name: r.name, moshafs: moshafs)
        }
    }

    /// `{base}{NNN}.mp3` — 3-digit zero-padded surah number appended to the moshaf's server base.
    public static func audioURL(serverBase: URL, surah: Int) -> URL {
        serverBase.appendingPathComponent(String(format: "%03d.mp3", surah))
    }
}
