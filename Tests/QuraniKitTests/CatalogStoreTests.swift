import Testing
import Foundation
@testable import QuraniKit

@MainActor @Test func loadsAndFilters() async throws {
    let store = CatalogStore()
    let json = #"{"reciters":[{"id":1,"name":"Mishary Alafasy","moshaf":[{"id":1,"name":"Hafs","server":"https://s/a/","surah_total":"1","surah_list":"1"}]},{"id":2,"name":"Sudais","moshaf":[{"id":1,"name":"Hafs","server":"https://s/b/","surah_list":"1"}]}]}"#.data(using:.utf8)!
    await store.load { json }
    #expect(store.reciters.count == 2)
    #expect(store.filtered(search: "ala", riwaya: nil).map(\.id) == [1])
    #expect(store.filtered(search: "", riwaya: "Hafs").count == 2)
}

/// Each riwaya chip must match the live feed's transliterated moshaf spellings, including
/// "Mojawwad" — the label "Mujawwad" otherwise hits nothing. (Muallim/"Mo'lim" is hidden
/// app-wide, see `hidesMuallimMoshafs`, so it has no chip.)
@MainActor @Test func riwayaChipsMatchLiveSpelling() {
    func reciter(_ id: Int, moshaf name: String) -> Reciter {
        Reciter(id: id, name: "Reciter \(id)", moshafs: [
            Moshaf(id: 1, name: name, serverBase: URL(string: "https://s/")!, surahNumbers: [1])
        ])
    }
    let store = CatalogStore()
    store.seed(reciters: [
        reciter(1, moshaf: "Rewayat Hafs A'n Assem"),
        reciter(2, moshaf: "Rewayat Warsh A'n Nafi'"),
        reciter(3, moshaf: "Almusshaf Al Mojawwad"),
    ])
    #expect(store.filtered(search: "", riwaya: "Hafs").map(\.id) == [1])
    #expect(store.filtered(search: "", riwaya: "Warsh").map(\.id) == [2])
    #expect(store.filtered(search: "", riwaya: "Mujawwad").map(\.id) == [3])
}

/// Muallim (teaching) recitations are hidden app-wide via `stripMuallim`, on both the seed
/// and live-feed paths: a Mo'lim/Mo'allim/Muallim moshaf is removed, and a reciter left with
/// no other moshaf is dropped entirely — so nothing surfaces it to the UI.
@MainActor @Test func hidesMuallimMoshafs() {
    let base = URL(string: "https://s/")!
    let store = CatalogStore()
    store.seed(reciters: [
        // keeps Hafs, loses the Mo'allim set
        Reciter(id: 1, name: "Mixed", moshafs: [
            Moshaf(id: 1, name: "Hafs", serverBase: base, surahNumbers: [1]),
            Moshaf(id: 2, name: "Almusshaf Al Mo'allim", serverBase: base, surahNumbers: [1]),
        ]),
        // muallim-only → dropped whole
        Reciter(id: 2, name: "Teacher", moshafs: [
            Moshaf(id: 3, name: "Muallim", serverBase: base, surahNumbers: [1]),
        ]),
    ])
    #expect(store.reciters.map(\.id) == [1])
    #expect(store.reciters.first?.moshafs.map(\.name) == ["Hafs"])
}
