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
