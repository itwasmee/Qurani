import Testing
import Foundation
@testable import QuraniKit

@Test func loadsFeaturedStations() throws {
    let s = try CuratedStations.load()
    #expect(s.count >= 4)
    let makkah = try #require(s.first { $0.id == "makkah_haram" })
    #expect(makkah.kind == .hls)
    #expect(makkah.hasVideo == true)
    #expect(makkah.url.absoluteString.hasPrefix("https://"))
    #expect(s.contains { $0.id == "egypt_quran_kareem" })
}

/// Pin every featured station's URL + kind + video flag so an accidental edit to
/// stations.json (the verified spec §6 endpoints) is caught by the suite.
@Test func featuredStationsPinnedToVerifiedEndpoints() throws {
    let s = try CuratedStations.load()
    func station(_ id: String) throws -> Station { try #require(s.first { $0.id == id }) }

    let makkah = try station("makkah_haram")
    #expect(makkah.kind == .hls)
    #expect(makkah.hasVideo == true)
    #expect(makkah.url.absoluteString == "https://cdn-globecast.akamaized.net/live/eds/saudi_quran/hls_roku/index.m3u8")

    let madinah = try station("madinah_nabawi")
    #expect(madinah.kind == .hls)
    #expect(madinah.hasVideo == true)
    #expect(madinah.url.absoluteString == "https://cdn-globecast.akamaized.net/live/eds/saudi_sunnah/hls_roku/index.m3u8")

    let egypt = try station("egypt_quran_kareem")
    #expect(egypt.kind == .icecast)
    #expect(egypt.hasVideo == false)
    #expect(egypt.url.absoluteString == "https://stream.radiojar.com/8s5u5tpdtwzuv")

    let saudi = try station("saudi_quran_radio")
    #expect(saudi.kind == .hls)
    #expect(saudi.hasVideo == false)
    #expect(saudi.url.absoluteString == "https://live.kwikmotion.com/sbrksaquranradiolive/srpksaquranradio/playlist.m3u8")
}
