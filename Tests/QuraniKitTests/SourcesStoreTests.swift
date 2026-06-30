import Testing
import Foundation
@testable import QuraniKit

@MainActor @Test func loadsFeaturedFromBundle() throws {
    let store = SourcesStore()
    try store.loadFeatured()
    #expect(store.featured.contains { $0.id == "makkah_haram" })
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
