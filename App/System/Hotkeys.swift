import KeyboardShortcuts
import QuraniKit

extension KeyboardShortcuts.Name { static let togglePlay = Self("togglePlay", default: .init(.space, modifiers: [.control, .option])) }

@MainActor enum Hotkeys {
    static func register(_ engine: PlaybackEngine) {
        KeyboardShortcuts.onKeyDown(for: .togglePlay) { [weak engine] in engine?.toggle() }
    }
}
