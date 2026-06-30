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
/// "Mojawwad"/"Mo'lim" — the labels "Mujawwad"/"Muallim" otherwise hit nothing.
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
        reciter(4, moshaf: "Almusshaf Al Mo'lim"),
    ])
    #expect(store.filtered(search: "", riwaya: "Hafs").map(\.id) == [1])
    #expect(store.filtered(search: "", riwaya: "Warsh").map(\.id) == [2])
    #expect(store.filtered(search: "", riwaya: "Mujawwad").map(\.id) == [3])
    #expect(store.filtered(search: "", riwaya: "Muallim").map(\.id) == [4])
}
