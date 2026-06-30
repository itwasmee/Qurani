import Testing
import Foundation
@testable import QuraniKit

@MainActor @Test func favoritesPersistAcrossInstances() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = FavoritesStore(directory: dir)
    #expect(a.reciterIDs.isEmpty)            // missing file (first run) → empty, no crash
    a.toggle(reciter: 7)
    let b = FavoritesStore(directory: dir)
    #expect(b.isFavorite(reciter: 7))        // a fresh instance reflects prior state
}

@MainActor @Test func mixPoolPersistsAcrossInstances() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = MixPoolStore(directory: dir)
    a.toggle(reciter: 11)
    let b = MixPoolStore(directory: dir)
    #expect(b.contains(11))
}

@MainActor @Test func togglingOffRemovesAndPersists() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = FavoritesStore(directory: dir)
    a.toggle(reciter: 5)                      // on
    a.toggle(reciter: 5)                      // off
    #expect(!a.isFavorite(reciter: 5))
    let b = FavoritesStore(directory: dir)
    #expect(!b.isFavorite(reciter: 5))        // the off state persisted
    #expect(b.reciterIDs.isEmpty)
}

@MainActor @Test func corruptBackingFileLoadsAsEmpty() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = FavoritesStore(directory: dir)
    a.toggle(reciter: 3)                      // create the backing file at whatever path the store uses
    let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
    #expect(!files.isEmpty)
    for f in files { try Data("not json{".utf8).write(to: f) }   // corrupt every backing file
    let b = FavoritesStore(directory: dir)
    #expect(b.reciterIDs.isEmpty)             // corrupt JSON → empty set, not a throw
}
