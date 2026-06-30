import Foundation

/// Decodes the mp3quran v3 `/reciters` payload into our `Reciter`/`Moshaf` models and
/// builds per-surah audio URLs. Pure logic — no networking lives here.
public enum CatalogService {
    private struct Payload: Decodable { let reciters: [RawReciter] }
    private struct RawReciter: Decodable { let id: Int; let name: String; let moshaf: [RawMoshaf] }
    // `server`/`surah_list` are optional: the live feed occasionally omits them on a single
    // moshaf, and JSONDecoder is all-or-nothing — a non-optional field would throw the ENTIRE
    // payload (all ~240 reciters) over one bad row. Optional lets us drop just that moshaf.
    private struct RawMoshaf: Decodable { let id: Int; let name: String; let server: String?; let surah_list: String? }

    /// Upgrades an `http://` server URL to `https://` (rewriting only the scheme prefix),
    /// leaving any other scheme untouched. Returns nil if the result isn't a valid URL.
    static func upgrade(_ s: String) -> URL? {
        var str = s
        if str.hasPrefix("http://") { str = "https://" + str.dropFirst("http://".count) }
        return URL(string: str)
    }

    /// Decodes reciters, dropping moshafs whose server URL is missing/empty/unusable and
    /// reciters left with no usable moshaf. A nil/missing `surah_list` yields empty
    /// `surahNumbers`; otherwise it is parsed (comma-separated, tolerant of spaces) → `[Int]`.
    /// One malformed moshaf is skipped, never thrown — the rest of the feed survives.
    public static func decodeReciters(_ data: Data) throws -> [Reciter] {
        try JSONDecoder().decode(Payload.self, from: data).reciters.compactMap { r in
            let moshafs = r.moshaf.compactMap { m -> Moshaf? in
                guard let server = m.server, !server.isEmpty, let base = upgrade(server) else { return nil }
                let nums = (m.surah_list ?? "").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
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
