import Foundation

/// Fetches, caches, and filters the mp3quran reciter catalog for the Explore view.
/// Decoding lives in `CatalogService`; networking is injected (closure) so the store
/// stays testable and the UI never sees a throw.
@MainActor public final class CatalogStore: ObservableObject {
    @Published public private(set) var reciters: [Reciter] = []

    public init() {}

    /// Decode the fetched payload into `reciters`. On any error (offline, malformed feed)
    /// the catalog is left empty rather than surfacing a throw to the UI.
    public func load(_ fetch: () async throws -> Data) async {
        do { reciters = try CatalogService.decodeReciters(try await fetch()) }
        catch { reciters = [] }
    }

    /// Inject already-decoded reciters directly. For SwiftUI previews and the
    /// `--snapshot` render path, which need deterministic content without a network.
    public func seed(reciters: [Reciter]) { self.reciters = reciters }

    /// Case-insensitive filter over the cached reciters.
    /// - `search`: matches reciter name by substring; empty string passes everything through.
    /// - `riwaya`: matches when any of the reciter's moshafs has a name containing one of the
    ///   chip's alias spellings (see `riwayaAliases`); nil (or empty) passes everything through.
    public func filtered(search: String, riwaya: String?) -> [Reciter] {
        reciters.filter { reciter in
            let nameOK = search.isEmpty
                || reciter.name.range(of: search, options: .caseInsensitive) != nil
            let riwayaOK: Bool
            if let riwaya, !riwaya.isEmpty {
                // Resolve the chip label to the spellings the live feed actually uses
                // (e.g. "Mujawwad" → "Mojawwad"); an unmapped token matches itself.
                let aliases = Self.riwayaAliases[riwaya] ?? [riwaya]
                riwayaOK = reciter.moshafs.contains { moshaf in
                    aliases.contains { moshaf.name.range(of: $0, options: .caseInsensitive) != nil }
                }
            } else {
                riwayaOK = true
            }
            return nameOK && riwayaOK
        }
    }

    /// Maps each riwaya chip label to the moshaf-name substrings that identify it in the live
    /// mp3quran feed, which transliterates some as "Mojawwad"/"Mo'lim" rather than the chip's
    /// display label. A match on any candidate (case-insensitive) counts; a label absent here
    /// falls back to matching itself, so arbitrary tokens still behave as plain substrings.
    static let riwayaAliases: [String: [String]] = [
        "Hafs": ["Hafs"],
        "Warsh": ["Warsh"],
        "Mujawwad": ["Mojawwad", "Mujawwad"],
        "Muallim": ["Mo'lim", "Mo'allim", "Muallim"],
    ]

    /// Fetches the live reciter catalog (English names). 15s timeout so a slow/dead host
    /// doesn't hang the Explore view.
    public static func fetchReciters() async throws -> Data {
        let url = URL(string: "https://www.mp3quran.net/api/v3/reciters?language=eng")!
        let request = URLRequest(url: url, timeoutInterval: 15)
        return try await URLSession.shared.data(for: request).0
    }
}
