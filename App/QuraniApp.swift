import SwiftUI
import QuraniKit

@main
struct QuraniApp: App {
    @StateObject private var model = AppModel()

    init() {
        #if DEBUG
        // Debug visual-review path: render PNGs and exit(0) before the scene installs.
        if let outDir = SnapshotRunner.requestedOutputDir() {
            SnapshotRunner.run(outDir: outDir)   // never returns
        }
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            GlassPanel(model: model, sources: model.sources, engine: model.engine,
                       catalog: model.catalog, favorites: model.favorites, pool: model.pool,
                       library: model.library, importer: model.importer, settings: model.settings,
                       surahs: model.surahs,
                       play: { model.playOnDemand(reciter: $0, moshaf: $1, surah: $2) },
                       playLocal: { model.playLocal($0) },
                       commitImports: { model.commitImports($0) })
                .task { await model.bootstrap() }
        } label: {
            EqualizerMenuBarLabel(engine: model.engine)
        }
        .menuBarExtraStyle(.window)
    }
}
