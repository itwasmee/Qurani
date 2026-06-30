import SwiftUI
import QuraniKit

@main
struct QuraniApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            GlassPanel(model: model, engine: model.engine)
                .task { await model.bootstrap() }
        } label: {
            EqualizerMenuBarLabel(engine: model.engine)
        }
        .menuBarExtraStyle(.window)
    }
}
