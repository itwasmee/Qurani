import Testing
import Foundation
@testable import QuraniKit

private let A = PoolMember(id: "a", source: .onDemand, displayName: "A", reciterName: "A", surahNumbers: [1, 2, 3], reciterID: 1, moshaf: nil)
private let B = PoolMember(id: "b", source: .local, displayName: "B", reciterName: "B", surahNumbers: [2], reciterID: nil, moshaf: nil)

@Test func inOrderAssignsAMemberThatHasEachSurah() {
    let q = MixEngine.buildQueue(pool: [A, B], config: MixConfig(order: .inOrder, range: .custom(1...3)),
                                 surahJuz: [:], pickIndex: { _ in 0 }, shuffle: { $0 })
    #expect(q.map(\.surah) == [1, 2, 3])
    // surah 1 only A has → A; surah 2 both → pickIndex 0; surah 3 only A
    #expect(q[0].memberID == "a"); #expect(q[2].memberID == "a")
}

@Test func skipsSurahsNoMemberHas() {
    let q = MixEngine.buildQueue(pool: [B], config: MixConfig(order: .inOrder, range: .custom(1...3)),
                                 surahJuz: [:], pickIndex: { _ in 0 }, shuffle: { $0 })
    #expect(q.map(\.surah) == [2])   // only surah 2 is available from B
}

@Test func shuffleUsesInjectedPermutation() {
    let q = MixEngine.buildQueue(pool: [A], config: MixConfig(order: .shuffle, range: .custom(1...3)),
                                 surahJuz: [:], pickIndex: { _ in 0 }, shuffle: { $0.reversed() })
    #expect(q.map(\.surah) == [3, 2, 1])
}

@Test func rangeFullIs1to114() {
    let q = MixEngine.buildQueue(pool: [A], config: MixConfig(order: .inOrder, range: .full),
                                 surahJuz: [:], pickIndex: { _ in 0 }, shuffle: { $0 })
    #expect(q.map(\.surah) == [1, 2, 3])   // A only has 1,2,3 so others skipped, but range was full 1...114
}

@Test func juzRangeFiltersBySurahJuz() {
    // surahJuz maps surah→starting juz; range .juz(1) keeps surahs whose juz==1
    let q = MixEngine.buildQueue(pool: [A], config: MixConfig(order: .inOrder, range: .juz(1)),
                                 surahJuz: [1: 1, 2: 1, 3: 3], pickIndex: { _ in 0 }, shuffle: { $0 })
    #expect(q.map(\.surah) == [1, 2])
}
