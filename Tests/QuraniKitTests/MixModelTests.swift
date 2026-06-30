import Testing
import Foundation
@testable import QuraniKit

@Test func poolMemberShapes() {
    let m = Moshaf(id: 3, name: "Hafs", serverBase: URL(string:"https://s/x/")!, surahNumbers: [1,2,67])
    let od = PoolMember(id: "od:9:3", source: .onDemand, displayName: "Sudais", reciterName: "Sudais", surahNumbers: [1,2,67], reciterID: 9, moshaf: m)
    #expect(od.surahNumbers.contains(67)); #expect(od.source == .onDemand)
    let lo = PoolMember(id: "local:Husary", source: .local, displayName: "Husary", reciterName: "Husary", surahNumbers: [2], reciterID: nil, moshaf: nil)
    #expect(lo.source == .local); #expect(MixConfig().order == .shuffle)
}
