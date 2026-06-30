import Testing
import Foundation
@testable import QuraniKit

private func track(_ reciter: String, _ surah: Int) -> LocalTrack {
    LocalTrack(bookmark: Data(), reciterName: reciter, surahNumber: surah, confidence: 1.0)
}

@MainActor @Test func libraryPersistsAcrossInstances() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = LibraryStore(directory: dir)
    #expect(a.tracks.isEmpty)                  // missing file (first run) → empty, no crash
    a.add([track("Husary", 1), track("Husary", 2)])
    let b = LibraryStore(directory: dir)       // fresh instance reflects prior state
    #expect(b.tracks.count == 2)
    #expect(Set(b.tracks.map(\.surahNumber)) == [1, 2])
}

@MainActor @Test func libraryAddDedupesByID() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = LibraryStore(directory: dir)
    let t = track("Husary", 1)
    store.add([t])
    store.add([t])                             // same id → not double-added
    #expect(store.tracks.count == 1)
}

@MainActor @Test func libraryGroupedSortsByReciterThenSurah() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = LibraryStore(directory: dir)
    store.add([track("B", 5), track("A", 2), track("A", 1)])
    let groups = store.grouped()
    #expect(groups.map(\.reciter) == ["A", "B"])
    #expect(groups[0].tracks.map(\.surahNumber) == [1, 2])
    #expect(groups[1].tracks.map(\.surahNumber) == [5])
}

@MainActor @Test func libraryRemovePersists() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = LibraryStore(directory: dir)
    let t = track("Husary", 1)
    a.add([t, track("Husary", 2)])
    a.remove(id: t.id)
    #expect(a.tracks.count == 1)
    let b = LibraryStore(directory: dir)        // removal persisted
    #expect(b.tracks.count == 1)
    #expect(!b.tracks.contains { $0.id == t.id })
}

@MainActor @Test func libraryResolveURLNilOnBadBookmark() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = LibraryStore(directory: dir)
    let t = track("Husary", 1)                  // synthetic Data() bookmark cannot resolve
    #expect(store.resolveURL(t) == nil)         // returns nil, does not crash
}

@MainActor @Test func libraryCorruptBackingFileLoadsAsEmpty() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = LibraryStore(directory: dir)
    a.add([track("Husary", 1)])                 // create the backing file
    let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
    #expect(!files.isEmpty)
    for f in files { try Data("not json{".utf8).write(to: f) }
    let b = LibraryStore(directory: dir)
    #expect(b.tracks.isEmpty)                   // corrupt JSON → empty, not a throw
}
