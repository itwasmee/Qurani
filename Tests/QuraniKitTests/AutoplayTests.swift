import Testing
@testable import QuraniKit

@Test func nextSurahMidListReturnsFollowing() {
    #expect(Autoplay.nextSurah(in: [1, 2, 3, 55, 67], after: 2) == 3)
}
@Test func nextSurahLastReturnsNil() {
    #expect(Autoplay.nextSurah(in: [1, 2, 3], after: 3) == nil)
}
@Test func nextSurahAbsentReturnsNil() {
    #expect(Autoplay.nextSurah(in: [1, 2, 3], after: 9) == nil)
}
@Test func nextSurahSingleReturnsNil() {
    #expect(Autoplay.nextSurah(in: [36], after: 36) == nil)
}
@Test func nextSurahNonContiguousReturnsNextInList() {
    #expect(Autoplay.nextSurah(in: [1, 36, 55, 112], after: 36) == 55)
}
