import SwiftUI
import QuraniKit

@main
struct QuraniApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Debug visual-review path: render PNGs and exit(0) before the scene installs.
        if let outDir = SnapshotRunner.requestedOutputDir() {
            SnapshotRunner.run(outDir: outDir)   // never returns
        }
    }

    var body: some Scene {
        MenuBarExtra {
            GlassPanel(sources: model.sources, engine: model.engine)
                .task { await model.bootstrap() }
        } label: {
            EqualizerMenuBarLabel(engine: model.engine)
        }
        .menuBarExtraStyle(.window)
    }
}
