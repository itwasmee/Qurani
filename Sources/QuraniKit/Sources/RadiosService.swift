import Foundation

public enum RadiosService {
    public static func rewriteHost(_ url: URL) -> URL {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.host == "backup.qurango.net" else { return url }
        c.host = "qurango.net"
        return c.url ?? url
    }

    private struct Payload: Decodable { let radios: [Radio] }
    private struct Radio: Decodable { let id: Int; let name: String; let url: URL }

    public static func decode(_ data: Data) throws -> [Station] {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return payload.radios.map { r in
            Station(id: "radio_\(r.id)", name: r.name, region: "24/7",
                    kind: .icecast, url: rewriteHost(r.url), reciter: r.name, hasVideo: false)
        }
    }
}
