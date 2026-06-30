import Foundation

/// The two user preferences that don't belong to the theme (`@AppStorage("theme")`) or the
/// library-data stores: the **media-keys** and **auto-import** toggles surfaced in Settings.
/// Persisted as JSON beside the other stores; a missing or corrupt file loads as the defaults
/// (both on). Mirrors `FavoritesStore` — the Application Support path is computed in-body via the
/// shared `IntSetStore.applicationSupportDirectory()`, and `init(directory:)` is injectable for tests.
@MainActor public final class SettingsStore: ObservableObject {
    /// Whether hardware media keys / Control Center transport drive playback. Wiring this to
    /// actually gate the remote-command targets is Task 2 — here it only persists the choice.
    @Published public var mediaKeysEnabled: Bool = true { didSet { save() } }
    /// Whether the watched library folder auto-imports (and smart-tags) new files.
    @Published public var autoImportEnabled: Bool = true { didSet { save() } }

    private let fileURL: URL
    /// Suppresses the `save()` that the init-body load triggers: the `= true` declarations mean the
    /// properties are already initialized, so assigning the loaded values fires `didSet`. Only real
    /// mutations after construction should persist (and a missing file must stay missing until then).
    private var loaded = false

    /// Designated init: load from `directory/settings.json`. A missing file (first run) or a
    /// corrupt/garbage file both keep the defaults rather than throwing. The directory need not
    /// exist yet; it is created on first write. Injectable for tests.
    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("settings.json")
        if let stored = Self.load(fileURL) {
            mediaKeysEnabled = stored.mediaKeysEnabled
            autoImportEnabled = stored.autoImportEnabled
        }
        loaded = true
    }

    /// Real path: `Application Support/Qurani/settings.json` — the support directory is computed
    /// (and created) inside the call, reusing the shared store helper rather than defaulting an arg.
    public convenience init() { self.init(directory: IntSetStore.applicationSupportDirectory()) }

    /// The on-disk shape. A small Codable so the persistence is one encode/decode and adding a
    /// preference later is a single field. A file that predates a new field (or any corruption)
    /// fails to decode and falls back wholesale to the defaults — same contract as `IntSetStore`.
    private struct Persisted: Codable {
        var mediaKeysEnabled = true
        var autoImportEnabled = true
    }

    /// Decode the JSON file; a missing or corrupt/garbage file yields nil → caller keeps defaults.
    private static func load(_ url: URL) -> Persisted? {
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Persisted.self, from: data)
        else { return nil }
        return value
    }

    /// Persist the current values as JSON, writing atomically (a crash mid-write can't leave a
    /// half-written file). Creates the parent directory if needed. A no-op until `init` has finished
    /// loading, so constructing a store to read never writes a file.
    private func save() {
        guard loaded else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let snapshot = Persisted(mediaKeysEnabled: mediaKeysEnabled, autoImportEnabled: autoImportEnabled)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
