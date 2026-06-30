import Foundation

public enum RadiosService {
    public static func rewriteHost(_ url: URL) -> URL {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.host == "backup.qurango.net" else { return url }
        c.host = "qurango.net"
        return c.url ?? url
    }

    private struct Payload: Decodable { let radios: [Radio] }
    // Tolerant row shape: `url` is decoded as String, then validated per-row. A single
    // malformed URL must skip only that station, not throw away the whole ~174-row catalog.
    private struct Radio: Decodable { let id: Int; let name: String; let url: String }

    public static func decode(_ data: Data) throws -> [Station] {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return payload.radios.compactMap { r -> Station? in
            guard let url = URL(string: r.url),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let host = url.host, !host.isEmpty
            else { return nil }
            return Station(id: "radio_\(r.id)", name: r.name, region: "24/7",
                           kind: .icecast, url: rewriteHost(url), reciter: r.name, hasVideo: false)
        }
    }
}
