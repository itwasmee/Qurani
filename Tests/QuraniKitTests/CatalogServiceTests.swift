import Testing
import Foundation
@testable import QuraniKit

@Test func decodesRecitersUpgradingHttp() throws {
    let json = """
    {"reciters":[{"id":123,"name":"Sudais","moshaf":[
      {"id":1,"name":"Hafs - Murattal","server":"http://server7.mp3quran.net/sds/","surah_total":"114","surah_list":"1,2,3,67,114"}]}]}
    """.data(using: .utf8)!
    let rs = try CatalogService.decodeReciters(json)
    #expect(rs.count == 1)
    let m = try #require(rs[0].moshafs.first)
    #expect(m.serverBase.scheme == "https")                 // http upgraded
    #expect(m.surahNumbers == [1,2,3,67,114])
    #expect(CatalogService.audioURL(serverBase: m.serverBase, surah: 67).absoluteString == "https://server7.mp3quran.net/sds/067.mp3")
}
