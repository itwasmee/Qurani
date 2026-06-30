import SwiftUI
import AppKit
import QuraniKit

// MARK: - Hex color helper (exact mockup tokens)

extension Color {
    /// `Color(hex: 0x37d6a4)` — sRGB from a 24-bit hex literal, with optional opacity.
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - Theme tokens (exact values from the approved mockups)

struct Tokens {
    let bg: Color
    let accent: Color
    let text: Color
    let muted: Color
    let gold: Color
    let glassTint: Color
    let isDark: Bool

    static func of(_ t: ResolvedTheme) -> Tokens {
        switch t {
        case .noor:   // dark
            return Tokens(bg: Color(hex: 0x0b0c0f),
                          accent: Color(hex: 0x37d6a4),
                          text: Color(hex: 0xf3f4f3),
                          muted: Color(hex: 0x9a9e9b),
                          gold: Color(hex: 0xe7c46a),
                          glassTint: Color(hex: 0x141615, opacity: 0.55),
                          isDark: true)
        case .sahar:  // light
            return Tokens(bg: Color(hex: 0xfbeede),
                          accent: Color(hex: 0x0e7c6b),
                          text: Color(hex: 0x2c2620),
                          muted: Color(hex: 0x6b5f50),
                          gold: Color(hex: 0xa98b5e),
                          glassTint: Color(hex: 0xfffaf3, opacity: 0.55),
                          isDark: false)
        case .layl:   // deep night
            return Tokens(bg: Color(hex: 0x0a0b18),
                          accent: Color(hex: 0xe7c46a),
                          text: Color(hex: 0xf6efdf),
                          muted: Color(hex: 0x9a9aa6),
                          gold: Color(hex: 0xe7c46a),
                          glassTint: Color(hex: 0x141626, opacity: 0.5),
                          isDark: true)
        }
    }
}

// MARK: - Real vibrancy glass

/// Behind-window vibrancy for the MenuBarExtra `.window` panel — the reliable
/// "glass" path for a menubar popover (vs. flat `.ultraThinMaterial`).
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var isDark: Bool = true

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) { configure(view) }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blending
        view.state = .active
        // Drive the material's light/dark variant explicitly so the glass tint
        // always reads correctly regardless of the host window's appearance.
        view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}
