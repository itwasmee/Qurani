import Testing
import Foundation
@testable import QuraniKit

@MainActor @Test func stationFavoriteTogglePersists() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("qurani-stationfav-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }

    let a = StationFavoritesStore(directory: dir)
    #expect(a.contains("sd_quran_digital") == false)
    a.toggle(station: "sd_quran_digital")
    a.toggle(station: "makkah_haram")
    #expect(a.contains("sd_quran_digital"))

    // Persists: a fresh instance over the same directory reloads the set.
    let b = StationFavoritesStore(directory: dir)
    #expect(b.contains("sd_quran_digital"))
    #expect(b.contains("makkah_haram"))

    // Toggling off removes + persists.
    b.toggle(station: "sd_quran_digital")
    #expect(b.contains("sd_quran_digital") == false)
    let c = StationFavoritesStore(directory: dir)
    #expect(c.contains("sd_quran_digital") == false)
    #expect(c.contains("makkah_haram"))
}

@MainActor @Test func stationFavoritesCorruptFileYieldsEmpty() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("qurani-stationfav-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data("not json".utf8).write(to: dir.appendingPathComponent("station_favorites.json"))
    #expect(StationFavoritesStore(directory: dir).ids.isEmpty)
}
