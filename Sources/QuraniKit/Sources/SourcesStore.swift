import Foundation

@MainActor public final class SourcesStore: ObservableObject {
    @Published public private(set) var featured: [Station] = []
    @Published public private(set) var reciterStations: [Station] = []
    private let bundle: Bundle
    // `.module` is generated as an internal accessor, so it cannot be a default
    // argument of a public initializer; expose it via a convenience init instead.
    public init(bundle: Bundle) { self.bundle = bundle }
    public convenience init() { self.init(bundle: .module) }

    public func loadFeatured() throws { featured = try CuratedStations.load(bundle: bundle) }

    #if DEBUG
    /// Inject already-decoded stations directly. For the `--snapshot` render path, which needs
    /// deterministic content without a network. DEBUG-only — not shipped in release.
    public func seed(featured: [Station], reciterStations: [Station]) {
        self.featured = featured
        self.reciterStations = reciterStations
    }
    #endif

    public func loadReciterStations(_ fetch: () async throws -> Data) async {
        do { reciterStations = try RadiosService.decode(try await fetch()) }
        catch { reciterStations = [] }   // offline: featured still works
    }

    public static func fetchRadios() async throws -> Data {
        let url = URL(string: "https://www.mp3quran.net/api/v3/radios?language=eng")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15   // don't hang bootstrap on a slow/dead catalog host
        return try await URLSession.shared.data(for: request).0
    }
}
