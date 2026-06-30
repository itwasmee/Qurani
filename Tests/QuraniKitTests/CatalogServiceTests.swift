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

// Resilience: a single bad moshaf in the live feed must not throw away the whole payload.

// (a) A moshaf missing `surah_list` decodes with empty surahNumbers instead of throwing.
@Test func moshafMissingSurahListDecodesEmpty() throws {
    let json = #"{"reciters":[{"id":1,"name":"A","moshaf":[{"id":9,"name":"Hafs","server":"https://s/a/"}]}]}"#.data(using: .utf8)!
    let rs = try CatalogService.decodeReciters(json)
    #expect(rs.count == 1)
    #expect(rs[0].moshafs.first?.surahNumbers == [])
}

// (b) Moshafs with empty/missing `server` are dropped; a reciter left with zero moshafs is
// dropped — while a healthy reciter in the same payload still decodes.
@Test func dropsUnusableServerAndEmptyReciter() throws {
    let json = #"{"reciters":[{"id":1,"name":"EmptyServer","moshaf":[{"id":1,"name":"Hafs","server":"","surah_list":"1"}]},{"id":2,"name":"MissingServer","moshaf":[{"id":1,"name":"Hafs","surah_list":"1"}]},{"id":3,"name":"Good","moshaf":[{"id":1,"name":"Hafs","server":"https://s/c/","surah_list":"2"}]}]}"#.data(using: .utf8)!
    let rs = try CatalogService.decodeReciters(json)
    #expect(rs.map(\.id) == [3])
}

// (c) `surah_list` tolerates leading/trailing spaces, garbage tokens, and double commas.
@Test func surahListToleratesSpacesGarbageAndDoubleCommas() throws {
    let json = #"{"reciters":[{"id":1,"name":"A","moshaf":[{"id":1,"name":"Hafs","server":"https://s/a/","surah_list":" 1 , 2,,foo, 3 ,"}]}]}"#.data(using: .utf8)!
    let rs = try CatalogService.decodeReciters(json)
    #expect(rs[0].moshafs.first?.surahNumbers == [1, 2, 3])
}
