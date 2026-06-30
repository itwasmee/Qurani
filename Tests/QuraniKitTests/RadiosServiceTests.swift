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
    #expect(stations[0].url.host == "qurango.net")
    #expect(stations[0].kind == .icecast)
    #expect(stations[0].reciter == "سعد الغامدي")
}
