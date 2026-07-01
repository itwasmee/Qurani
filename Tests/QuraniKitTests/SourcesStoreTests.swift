import Testing
import Foundation
@testable import QuraniKit

@MainActor @Test func loadsFeaturedFromBundle() throws {
    let store = SourcesStore()
    try store.loadFeatured()
    #expect(store.featured.contains { $0.id == "makkah_haram" })
}

@MainActor @Test func loadsWorldRadioFromBundle() throws {
    let store = SourcesStore()
    try store.loadWorld()
    #expect(store.world.count == 37)
    #expect(store.world.contains { $0.id == "sd_quran_digital" })   // Sudan
    #expect(store.world.contains { $0.id == "ae_abudhabi_quran" && $0.kind == .hls })
    // Every row is well-formed: non-empty id/name, http(s) url with a host.
    for s in store.world {
        #expect(!s.id.isEmpty && !s.name.isEmpty)
        #expect(s.url.scheme == "http" || s.url.scheme == "https")
        #expect(s.url.host?.isEmpty == false)
    }
}

@MainActor @Test func loadsReciterStationsViaInjectedFetch() async throws {
    let store = SourcesStore()
    let json = #"{"radios":[{"id":7,"name":"الغامدي","url":"https://backup.qurango.net/radio/g"}]}"#.data(using: .utf8)!
    await store.loadReciterStations { json }
    #expect(store.reciterStations.first?.url.host == "qurango.net")
}

@MainActor @Test func reciterStationsEmptyOnFetchFailure() async throws {
    let store = SourcesStore()
    try store.loadFeatured()
    struct Boom: Error {}
    await store.loadReciterStations { throw Boom() }
    #expect(store.reciterStations.isEmpty)
    #expect(store.featured.contains { $0.id == "makkah_haram" })
}
