import Testing
import Foundation
@testable import QuraniKit

@Test func rewritesBackupHost() {
    let bad = URL(string: "https://backup.qurango.net/radio/saad_alghamdi")!
    #expect(RadiosService.rewriteHost(bad).absoluteString == "https://qurango.net/radio/saad_alghamdi")
    let ok = URL(string: "https://qurango.net/radio/x")!
    #expect(RadiosService.rewriteHost(ok) == ok)
}

@Test func decodesRadiosPayloadAndRewrites() throws {
    let json = """
    {"radios":[
      {"id":1,"name":"سعد الغامدي","url":"https://backup.qurango.net/radio/saad_alghamdi"},
      {"id":2,"name":"مشاري العفاسي","url":"https://qurango.net/radio/mishari"}
    ]}
    """.data(using: .utf8)!
    let stations = try RadiosService.decode(json)
    #expect(stations.count == 2)
    // Row 0: rewritten host + all synthesized fields.
    #expect(stations[0].id == "radio_1")
    #expect(stations[0].url.host == "qurango.net")
    #expect(stations[0].kind == .icecast)
    #expect(stations[0].region == "24/7")
    #expect(stations[0].hasVideo == false)
    #expect(stations[0].reciter == "سعد الغامدي")
    // Row 1: already-canonical host preserved untouched; second row not dropped.
    #expect(stations[1].id == "radio_2")
    #expect(stations[1].url.absoluteString == "https://qurango.net/radio/mishari")
    #expect(stations[1].reciter == "مشاري العفاسي")
}

@Test func decodeSkipsMalformedRowsInsteadOfDiscardingAll() throws {
    let json = """
    {"radios":[
      {"id":1,"name":"Good","url":"https://qurango.net/radio/a"},
      {"id":2,"name":"NoHost","url":"http://"},
      {"id":3,"name":"HasSpaces","url":"not a url at all"},
      {"id":4,"name":"AlsoGood","url":"https://backup.qurango.net/radio/c"}
    ]}
    """.data(using: .utf8)!
    let stations = try RadiosService.decode(json)
    #expect(stations.count == 2)                       // the two bad rows dropped, not all four
    #expect(stations.map(\.id) == ["radio_1", "radio_4"])
    #expect(stations[1].url.host == "qurango.net")     // row 4 still host-rewritten
}
