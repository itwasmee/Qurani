import Foundation

/// A newer build published on GitHub Releases.
public struct UpdateInfo: Equatable, Sendable {
    /// Display version — the release tag with any leading `v` stripped (`"1.1"`).
    public let version: String
    /// The `Qurani.zip` asset to download, or nil when the release has no zip asset
    /// (the UI then falls back to opening `releasePage`).
    public let zipURL: URL?
    /// The release's page on GitHub — the manual fallback and "release notes" link.
    public let releasePage: URL

    public init(version: String, zipURL: URL?, releasePage: URL) {
        self.version = version; self.zipURL = zipURL; self.releasePage = releasePage
    }
}

/// Queries GitHub's `releases/latest` API and compares the tag against the running build.
/// Pure check + state only — downloading and swapping the bundle live in the app target
/// (they need AppKit / Process), so this stays unit-testable via the injected `fetch`.
@MainActor public final class UpdateChecker: ObservableObject {
    public enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateInfo)
        case failed(String)
    }

    @Published public private(set) var state: State = .idle

    /// The one seam: fetch bytes for a URL. Production default is a plain ephemeral URLSession;
    /// tests inject canned JSON or a thrown error.
    public typealias Fetch = @Sendable (URL) async throws -> Data

    private let currentVersion: String
    private let latestReleaseURL: URL
    private let fetch: Fetch
    /// UserDefaults key holding the epoch of the last *automatic* check (manual checks also
    /// refresh it — a manual check satisfies the daily cadence).
    private static let lastCheckKey = "updateLastCheckAt"

    /// - Parameters:
    ///   - currentVersion: the running build's `CFBundleShortVersionString`.
    ///   - repo: `owner/name` on GitHub.
    ///   - fetch: transport seam; defaults to URLSession.
    public init(currentVersion: String, repo: String = "itwasmee/Qurani",
                fetch: @escaping Fetch = UpdateChecker.urlSessionFetch) {
        self.currentVersion = currentVersion
        self.latestReleaseURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        self.fetch = fetch
    }

    public static let urlSessionFetch: Fetch = { url in
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// One check: `.checking` → `.upToDate` / `.available` / `.failed`. Any error (offline,
    /// rate-limited, malformed JSON) lands in `.failed` with a short message — never throws.
    public func check() async {
        state = .checking
        do {
            let release = try JSONDecoder().decode(LatestRelease.self, from: try await fetch(latestReleaseURL))
            let remote = Self.normalize(release.tag_name)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            if Self.isNewer(remote, than: currentVersion) {
                let zip = release.assets.first { $0.name == "Qurani.zip" }?.browser_download_url
                state = .available(UpdateInfo(version: remote, zipURL: zip, releasePage: release.html_url))
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed("Couldn't check for updates")
        }
    }

    /// Run `check()` only when the daily cadence is due and no update is already staged —
    /// the silent auto-check the panel triggers on open. Never interrupts an `.available` state.
    public func autoCheckIfDue(now: Date = Date()) async {
        if case .available = state { return }
        let stamp = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        let last: Date? = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        guard Self.isAutoCheckDue(last: last, now: now) else { return }
        await check()
        // An auto-check that finds nothing (or fails) returns the row to idle — "You're up to
        // date" / an error toast is only meaningful right after an explicit manual check.
        if state == .upToDate { state = .idle }
        if case .failed = state { state = .idle }
    }

    /// Daily cadence: due when never checked or the last check is over 24h old. Pure for tests.
    public nonisolated static func isAutoCheckDue(last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) > 86_400
    }

    // MARK: - Version comparison

    /// Numeric dotted comparison (`1.10` > `1.9`), missing components read as 0
    /// (`1.0` == `1.0.0`), leading `v` stripped. A remote with no digits is never newer,
    /// so a malformed tag can't nag users with a phantom update.
    public nonisolated static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = components(remote), l = components(local)
        guard !r.isEmpty else { return false }
        for i in 0..<max(r.count, l.count) {
            let a = i < r.count ? r[i] : 0
            let b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    private nonisolated static func normalize(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    private nonisolated static func components(_ version: String) -> [Int] {
        let parts = normalize(version).split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        return parts.contains(where: { $0 > 0 }) || normalize(version).first?.isNumber == true ? parts : []
    }

    // MARK: - GitHub API shape

    /// The slice of `releases/latest` we read. Snake-case keys kept verbatim (one-shot decode).
    private struct LatestRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let html_url: URL
        let assets: [Asset]
    }
}
