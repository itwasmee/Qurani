import Testing
import Foundation
@testable import QuraniKit

@Test func loadsAll114SurahsSorted() throws {
    let surahs = try QuranData.loadSurahs()
    #expect(surahs.count == 114)
    #expect(surahs.first?.number == 1)
    #expect(surahs.last?.number == 114)
    #expect(surahs.map(\.number) == Array(1...114))
}

@Test func mulkIsVowelizedWithMetadata() throws {
    let surahs = try QuranData.loadSurahs()
    let mulk = try #require(QuranData.surah(67, in: surahs))
    #expect(mulk.nameAr.unicodeScalars.contains("\u{0652}"))  // contains sukun scalar (tashkeel present)
    #expect(mulk.translit == "Al-Mulk")
    #expect(mulk.ayahCount == 30)
    #expect(mulk.makki == true)
}
