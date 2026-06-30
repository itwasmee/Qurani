import Testing
import Foundation
@testable import QuraniKit

@MainActor @Test func settingsDefaultToOnWhenFileMissing() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = SettingsStore(directory: dir)
    #expect(a.mediaKeysEnabled)              // missing file (first run) → defaults, no crash
    #expect(a.autoImportEnabled)
}

@MainActor @Test func mediaKeysToggleOffPersistsAcrossInstances() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = SettingsStore(directory: dir)
    a.mediaKeysEnabled = false               // toggle off
    let b = SettingsStore(directory: dir)
    #expect(!b.mediaKeysEnabled)             // a fresh instance reflects the persisted off state
    #expect(b.autoImportEnabled)             // the untouched preference keeps its default
}

@MainActor @Test func autoImportToggleOffPersistsAcrossInstances() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = SettingsStore(directory: dir)
    a.autoImportEnabled = false
    let b = SettingsStore(directory: dir)
    #expect(!b.autoImportEnabled)
    #expect(b.mediaKeysEnabled)
}

@MainActor @Test func corruptSettingsFileLoadsAsDefaults() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = SettingsStore(directory: dir)
    a.mediaKeysEnabled = false                // create the backing file at whatever path the store uses
    let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
    #expect(!files.isEmpty)
    for f in files { try Data("not json{".utf8).write(to: f) }   // corrupt every backing file
    let b = SettingsStore(directory: dir)
    #expect(b.mediaKeysEnabled)               // corrupt JSON → defaults, not a throw
    #expect(b.autoImportEnabled)
}
