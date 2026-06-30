import Testing
@testable import QuraniKit

private let SAMPLE = [
    Surah(number: 1, nameAr: "الْفَاتِحَة", translit: "Al-Fatiha", nameEn: "The Opening", ayahCount: 7, makki: true, juz: 1),
    Surah(number: 2, nameAr: "الْبَقَرَة", translit: "Al-Baqarah", nameEn: "The Cow", ayahCount: 286, makki: false, juz: 1),
    Surah(number: 67, nameAr: "الْمُلْك", translit: "Al-Mulk", nameEn: "The Sovereignty", ayahCount: 30, makki: true, juz: 29),
]

@Test func everyayahNumber() {
    let g = Tagger.guess(filename: "067", folder: "Alafasy", tags: [:], surahs: SAMPLE)
    #expect(g.surahNumber == 67)
    #expect(g.reciterName == "Alafasy")
    #expect(g.confidence >= 0.8)
}

@Test func dashedNameAndSurahName() {
    let g = Tagger.guess(filename: "Sudais - Al-Mulk", folder: nil, tags: [:], surahs: SAMPLE)
    #expect(g.surahNumber == 67)
    #expect(g.reciterName == "Sudais")
}

@Test func unknownReciterLowConfidence() {
    let g = Tagger.guess(filename: "track12", folder: nil, tags: [:], surahs: SAMPLE)
    #expect(g.reciterName == nil)
    #expect(g.confidence <= 0.4)
}

@Test func tagsFallback() {
    let g = Tagger.guess(filename: "002", folder: nil, tags: ["artist": "Husary"], surahs: SAMPLE)
    #expect(g.reciterName == "Husary")
    #expect(g.surahNumber == 2)
}
