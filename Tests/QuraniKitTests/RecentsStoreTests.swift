import Testing
import Foundation
@testable import QuraniKit

@MainActor private func tmpDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("qurani-recents-\(UUID().uuidString)")
}
private func live(_ id: String) -> RecentItem {
    RecentItem(sourceID: "live:\(id)", kind: .live, title: id, subtitle: "r", stationID: id)
}

@MainActor @Test func recordDedupesAndMovesToFront() throws {
    let dir = tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let s = RecentsStore(directory: dir)
    s.record(live("a")); s.record(live("b")); s.record(live("a"))
    #expect(s.items.map(\.sourceID) == ["live:a", "live:b"])   // 'a' moved to front, not duplicated
}

@MainActor @Test func recordCapsAtLimit() throws {
    let dir = tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let s = RecentsStore(directory: dir, limit: 3)
    for i in 0..<6 { s.record(live("s\(i)")) }
    #expect(s.items.count == 3)
    #expect(s.items.first?.sourceID == "live:s5")   // newest kept
    #expect(!s.items.contains { $0.sourceID == "live:s0" })   // oldest dropped
}

@MainActor @Test func recentsPersistAcrossInstances() throws {
    let dir = tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let a = RecentsStore(directory: dir)
    a.record(RecentItem(sourceID: "ondemand:7:1:2", kind: .onDemand, title: "Al-Baqarah", subtitle: "Sudais",
                        reciterID: 7, reciterName: "Sudais", moshafID: 1, serverBase: "https://x/", surahNumber: 2))
    let b = RecentsStore(directory: dir)
    #expect(b.items.first?.sourceID == "ondemand:7:1:2")
    #expect(b.items.first?.surahNumber == 2)
    #expect(b.items.first?.serverBase == "https://x/")   // reconstruction fields survive the round-trip
}

@MainActor @Test func recentsCorruptFileYieldsEmpty() throws {
    let dir = tmpDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data("garbage".utf8).write(to: dir.appendingPathComponent("recents.json"))
    #expect(RecentsStore(directory: dir).items.isEmpty)
}
