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
