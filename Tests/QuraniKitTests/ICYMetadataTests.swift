import Testing
@testable import QuraniKit

private let sample = [
    Surah(number: 67, nameAr: "الْمُلْك", translit: "Al-Mulk", nameEn: "The Sovereignty", ayahCount: 30, makki: true, juz: 29),
    Surah(number: 1, nameAr: "الْفَاتِحَة", translit: "Al-Fatiha", nameEn: "The Opening", ayahCount: 7, makki: true, juz: 1)
]

@Test func findsSurahByTranslitInStreamTitle() {
    #expect(ICYMetadata.surahHint(from: "Sudais - Al-Mulk", surahs: sample) == "الْمُلْك")
}
@Test func findsSurahByArabicNameIgnoringTashkeel() {
    #expect(ICYMetadata.surahHint(from: "سورة الملك", surahs: sample) == "الْمُلْك")
}
@Test func returnsNilForGenericTitle() {
    #expect(ICYMetadata.surahHint(from: "Mini2's Broadcast", surahs: sample) == nil)
}
