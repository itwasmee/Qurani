import Foundation

public enum CuratedStations {
    public static func load(bundle: Bundle) throws -> [Station] {
        guard let url = bundle.url(forResource: "stations", withExtension: "json") else {
            throw NSError(domain: "CuratedStations", code: 1, userInfo: [NSLocalizedDescriptionKey: "stations.json missing"])
        }
        return try JSONDecoder().decode([Station].self, from: Data(contentsOf: url))
    }
    // `.module` is generated as an internal accessor, so it cannot be a default
    // argument of a public method; supply it from inside the body via this overload.
    public static func load() throws -> [Station] {
        try load(bundle: .module)
    }
}
