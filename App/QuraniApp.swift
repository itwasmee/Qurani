import SwiftUI
import QuraniKit

@main
struct QuraniApp: App {
    @StateObject private var model = AppModel()

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
