import Testing
import Foundation
@testable import QuraniKit

// MARK: - Version comparison

@Test func newerMinorVersionIsNewer() {
    #expect(UpdateChecker.isNewer("1.1", than: "1.0"))
}

@Test func newerPatchWithMoreComponentsIsNewer() {
    #expect(UpdateChecker.isNewer("1.0.1", than: "1.0"))   // missing components read as 0
}

@Test func equalVersionsAreNotNewer() {
    #expect(!UpdateChecker.isNewer("1.0", than: "1.0"))
    #expect(!UpdateChecker.isNewer("1.0.0", than: "1.0"))  // trailing zeros equal
}

@Test func olderVersionIsNotNewer() {
    #expect(!UpdateChecker.isNewer("1.0", than: "1.1"))
    #expect(!UpdateChecker.isNewer("0.9.9", than: "1.0"))
}

@Test func vPrefixIsStripped() {
    #expect(UpdateChecker.isNewer("v1.1", than: "1.0"))
    #expect(UpdateChecker.isNewer("v2.0", than: "v1.9"))
}

@Test func numericNotLexicographicComparison() {
    #expect(UpdateChecker.isNewer("1.10", than: "1.9"))    // 10 > 9 despite "1" < "9" as text
}

@Test func garbageRemoteVersionIsNotNewer() {
    #expect(!UpdateChecker.isNewer("latest", than: "1.0")) // no digits → never offer an update
    #expect(!UpdateChecker.isNewer("", than: "1.0"))
}

// MARK: - check() against an injected transport

private let sampleRelease = #"""
{
  "tag_name": "v9.9",
  "html_url": "https://github.com/itwasmee/Qurani/releases/tag/v9.9",
  "assets": [
    {"name": "Qurani.dmg", "browser_download_url": "https://github.com/itwasmee/Qurani/releases/download/v9.9/Qurani.dmg"},
    {"name": "Qurani.zip", "browser_download_url": "https://github.com/itwasmee/Qurani/releases/download/v9.9/Qurani.zip"}
  ]
}
"""#.data(using: .utf8)!

@MainActor @Test func newerReleaseBecomesAvailable() async {
    let checker = UpdateChecker(currentVersion: "1.0", fetch: { _ in sampleRelease })
    await checker.check()
    guard case .available(let info) = checker.state else {
        Issue.record("expected .available, got \(checker.state)"); return
    }
    #expect(info.version == "9.9")                                     // v prefix stripped for display
    #expect(info.zipURL?.lastPathComponent == "Qurani.zip")            // picked the zip asset, not the dmg
    #expect(info.releasePage.absoluteString.hasSuffix("/tag/v9.9"))
}

@MainActor @Test func matchingReleaseIsUpToDate() async {
    let checker = UpdateChecker(currentVersion: "9.9", fetch: { _ in sampleRelease })
    await checker.check()
    #expect(checker.state == .upToDate)
}

@MainActor @Test func olderReleaseIsUpToDate() async {
    // A remote older than the running build (e.g. a dev build ahead of the last tag) offers nothing.
    let checker = UpdateChecker(currentVersion: "10.0", fetch: { _ in sampleRelease })
    await checker.check()
    #expect(checker.state == .upToDate)
}

@MainActor @Test func fetchErrorBecomesFailed() async {
    struct Offline: Error {}
    let checker = UpdateChecker(currentVersion: "1.0", fetch: { _ in throw Offline() })
    await checker.check()
    guard case .failed = checker.state else {
        Issue.record("expected .failed, got \(checker.state)"); return
    }
}

@MainActor @Test func undecodableResponseBecomesFailed() async {
    let checker = UpdateChecker(currentVersion: "1.0", fetch: { _ in Data("not json".utf8) })
    await checker.check()
    guard case .failed = checker.state else {
        Issue.record("expected .failed, got \(checker.state)"); return
    }
}

@MainActor @Test func missingZipAssetStillAvailableViaReleasePage() async {
    let noZip = #"{"tag_name": "v9.9", "html_url": "https://github.com/itwasmee/Qurani/releases/tag/v9.9", "assets": []}"#
        .data(using: .utf8)!
    let checker = UpdateChecker(currentVersion: "1.0", fetch: { _ in noZip })
    await checker.check()
    guard case .available(let info) = checker.state else {
        Issue.record("expected .available, got \(checker.state)"); return
    }
    #expect(info.zipURL == nil)   // UI falls back to opening the release page
}

// MARK: - Auto-check throttle

@Test func autoCheckDueWhenNeverChecked() {
    #expect(UpdateChecker.isAutoCheckDue(last: nil, now: Date(timeIntervalSince1970: 1_000_000)))
}

@Test func autoCheckNotDueWithinADay() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(!UpdateChecker.isAutoCheckDue(last: now.addingTimeInterval(-3600), now: now))
}

@Test func autoCheckDueAfterADay() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(UpdateChecker.isAutoCheckDue(last: now.addingTimeInterval(-90_000), now: now))
}

// MARK: - SettingsStore: the auto-update toggle persists

@MainActor @Test func autoUpdateCheckDefaultsOnAndPersistsOff() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = SettingsStore(directory: dir)
    #expect(a.autoUpdateCheckEnabled == true)      // default on
    a.autoUpdateCheckEnabled = false
    let b = SettingsStore(directory: dir)          // reload from disk
    #expect(b.autoUpdateCheckEnabled == false)
    #expect(b.autoplayEnabled)                     // untouched preference keeps its default
}
