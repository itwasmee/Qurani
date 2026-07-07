import AppKit
import QuraniKit

/// Downloads a release zip, swaps the running .app bundle in place, clears the quarantine bit,
/// and relaunches — the in-app equivalent of `docs/get.sh`. Owned by `AppModel` (must outlive the
/// Settings screen that drives it); `SettingsView` observes `phase` for the row's live status.
///
/// The swap is move-aside/move-in on the bundle's own volume, with rollback if the new build
/// can't land. When the destination isn't writable by this user, it retries the swap through
/// `osascript … with administrator privileges` — the native password prompt, mirroring get.sh's
/// sudo fallback. Downloading and tool runs happen off the main actor (the password sheet can
/// sit open indefinitely); only `phase` updates hop back. On success `relaunch()` never returns.
@MainActor final class SelfUpdater: ObservableObject {
    enum Phase: Equatable {
        case idle
        /// Download fraction 0…1, or nil while the size is unknown (no Content-Length yet).
        case downloading(Double?)
        case installing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    private var running = false

    /// Download + install `info`. A release without a zip asset falls back to opening its GitHub
    /// page (the manual path). Errors land in `.failed` and leave the app untouched — the running
    /// bundle is only moved aside once the new one has fully downloaded, extracted, and validated.
    func install(_ info: UpdateInfo) async {
        guard !running else { return }
        guard let zip = info.zipURL else {
            NSWorkspace.shared.open(info.releasePage)
            return
        }
        running = true
        defer { running = false }
        do {
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("qurani-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let zipFile = staging.appendingPathComponent("Qurani.zip")

            phase = .downloading(nil)
            try await Self.download(zip, to: zipFile) { [weak self] fraction in
                Task { @MainActor in
                    if case .downloading = self?.phase { self?.phase = .downloading(fraction) }
                }
            }

            phase = .installing
            let newApp = try await Self.extract(zipFile, in: staging)
            try Self.validate(newApp, expecting: Bundle.main.bundleIdentifier)
            try await Self.swapIn(newApp, dest: Bundle.main.bundleURL)
            relaunch()   // terminates the process; never returns
        } catch let error as UpdateError {
            phase = .failed(error.message)
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed("Download failed — check your connection")
        }
    }

    // MARK: - Steps (nonisolated: run off the main actor)

    /// Stream the zip to disk, reporting coarse progress (1% steps — not per-chunk churn).
    private nonisolated static func download(
        _ url: URL, to file: URL, onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw UpdateError("Download failed (HTTP \(http.statusCode))")
        }
        let expected = response.expectedContentLength   // -1 when the server doesn't say
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }

        let flushSize = 256 * 1024
        var chunk = Data(capacity: flushSize)
        var received: Int64 = 0
        var lastShown = -1
        for try await byte in bytes {
            chunk.append(byte)
            if chunk.count >= flushSize {
                try handle.write(contentsOf: chunk)
                received += Int64(chunk.count)
                chunk.removeAll(keepingCapacity: true)
                if expected > 0 {
                    let pct = Int(Double(received) / Double(expected) * 100)
                    if pct != lastShown { lastShown = pct; onProgress(Double(pct) / 100) }
                }
            }
        }
        try handle.write(contentsOf: chunk)
    }

    /// Unpack with `ditto -x -k` (same tool get.sh uses — preserves symlinks and the executable
    /// bits a naive unzip can drop) and locate the app inside.
    private nonisolated static func extract(_ zip: URL, in dir: URL) async throws -> URL {
        let unpack = dir.appendingPathComponent("unpack")
        try await run("/usr/bin/ditto", ["-x", "-k", zip.path, unpack.path],
                      failure: "Couldn't unpack the update")
        let direct = unpack.appendingPathComponent("Qurani.app")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        // The zip may nest the bundle one level down; look one level deep before giving up.
        for entry in (try? FileManager.default.contentsOfDirectory(at: unpack, includingPropertiesForKeys: nil)) ?? [] {
            let nested = entry.appendingPathComponent("Qurani.app")
            if FileManager.default.fileExists(atPath: nested.path) { return nested }
        }
        throw UpdateError("The update didn't contain Qurani.app")
    }

    /// Refuse to swap in a bundle that isn't this app (a repurposed release asset, a corrupted
    /// download that still unzipped) — the only cheap integrity check an unsigned app can make.
    private nonisolated static func validate(_ app: URL, expecting bundleID: String?) throws {
        guard let expected = bundleID, let bundle = Bundle(url: app),
              bundle.bundleIdentifier == expected else {
            throw UpdateError("The downloaded app failed verification")
        }
    }

    /// Move the running bundle aside (legal while running — macOS keeps the mapped binary alive),
    /// drop the new one into its place, then clear quarantine. The aside copy lives beside the
    /// destination so the moves are same-volume renames; a failed second move rolls the old app
    /// back. A permissions failure retries the whole swap through the native admin prompt.
    private nonisolated static func swapIn(_ newApp: URL, dest: URL) async throws {
        let fm = FileManager.default
        let aside = dest.deletingLastPathComponent()
            .appendingPathComponent(".Qurani-old-\(UUID().uuidString)")
        do {
            try fm.moveItem(at: dest, to: aside)
            do {
                try fm.moveItem(at: newApp, to: dest)
            } catch {
                try? fm.moveItem(at: aside, to: dest)   // roll back — never leave no app at all
                throw error
            }
            try? fm.removeItem(at: aside)
            try? await run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dest.path],
                           failure: "")   // best-effort: URLSession downloads aren't quarantined
        } catch {
            try await adminSwapIn(newApp, dest: dest)
        }
    }

    /// The get.sh `sudo` path, in-app: one `do shell script … with administrator privileges`
    /// showing the standard macOS password sheet. Throws (→ `.failed`) if the user cancels.
    private nonisolated static func adminSwapIn(_ newApp: URL, dest: URL) async throws {
        let cmd = "rm -rf \(quoted(dest.path)) && mv \(quoted(newApp.path)) \(quoted(dest.path))"
            + " && xattr -dr com.apple.quarantine \(quoted(dest.path))"
        let escaped = cmd
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        try await run("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"],
                      failure: "Update needs permission to replace the app")
    }

    /// Detach a shell that reopens the (now-replaced) bundle after this process exits, then quit.
    private func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.4; /usr/bin/open \(Self.quoted(Bundle.main.bundleURL.path))"]
        try? p.run()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Small helpers

    private struct UpdateError: Error {
        let message: String
        init(_ m: String) { message = m }
    }

    /// Run a tool to completion off the calling actor; a non-zero exit (or failed launch) becomes
    /// `UpdateError(failure)`. Call sites that pass a `try?` treat the tool as best-effort.
    private nonisolated static func run(_ tool: String, _ args: [String], failure: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { proc in
                if proc.terminationStatus == 0 { cont.resume() }
                else { cont.resume(throwing: UpdateError(failure)) }
            }
            do { try p.run() } catch { cont.resume(throwing: UpdateError(failure)) }
        }
    }

    /// Single-quote a path for /bin/sh (`'…'`, embedded quotes closed-escaped-reopened).
    private nonisolated static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
