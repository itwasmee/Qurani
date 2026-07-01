import SwiftUI
import AppKit
import KeyboardShortcuts
import QuraniKit

/// The full Settings screen, presented as a full-panel overlay from the header gear (and the ••• menu's
/// "Settings…"). Mirrors `settings.html`: APPEARANCE theme swatches, the Play/Pause global-hotkey
/// recorder + media-keys toggle, the LIBRARY folder row + auto-import toggle, GENERAL launch-at-login,
/// and the About/attribution footer.
///
/// Design choices (documented per the brief):
///   • **Theme is the live `@AppStorage("theme")`** — read+written here, so tapping a swatch re-themes
///     the whole panel exactly as the old gear-menu picker did (GlassPanel reads the same reactive key
///     and recomputes the `tokens` it hands down). `tokens` arrive as a plain `let`, matching how every
///     tab view is themed; they refresh on the next render after a swatch tap.
///   • **The `KeyboardShortcuts.Recorder` supersedes the mockup's static `⌃ ⌥ Space` chips + "Record"
///     button** — one control both shows the current shortcut and records a new one (the package's
///     native affordance), wired to the Plan-1 `.togglePlay` name.
///   • **Change re-reads the folder path via a local refresh token** — `importer.libraryFolderURL` is a
///     computed property the importer doesn't publish, so a `@State` bump forces the row to re-read it
///     after `chooseLibraryFolder()` returns (its panel runs modally, so the new path is ready).
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var importer: LibraryImporter
    let tokens: Tokens
    let onClose: () -> Void

    @AppStorage("theme") private var themeRaw: String = Theme.system.rawValue
    /// Bumped after `chooseLibraryFolder()` so the folder-path row re-reads the (unpublished) URL.
    @State private var folderRefresh = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    appearanceSection
                    hotkeyRow
                    mediaKeysRow
                    autoplayRow
                    sectionLabel("LIBRARY")
                    libraryFolderRow
                    autoImportRow
                    sectionLabel("GENERAL")
                    launchAtLoginRow
                    about
                }
                .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(panelBackground)
    }

    // MARK: - Header (back / close)

    private var header: some View {
        HStack(spacing: 0) {
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                    Text("Settings").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(tokens.text)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close Settings")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15).padding(.top, 13).padding(.bottom, 11)
        .overlay(alignment: .bottom) { hairline(tokens.isDark ? 0.07 : 0.10) }
    }

    // MARK: - Appearance (theme swatches)

    private var appearanceSection: some View {
        VStack(spacing: 0) {
            sectionLabel("APPEARANCE")
            HStack(spacing: 9) {
                swatch(.system, "System")
                swatch(.sahar, "Sahar")
                swatch(.noor, "Noor")
                swatch(.layl, "Layl")
            }
            .padding(.horizontal, 16).padding(.bottom, 6)
        }
    }

    /// One theme swatch: the theme's signature gradient (Layl adds a moon), a 2px accent ring + ✓ when
    /// it's the current selection, and a label that brightens when selected. Tapping writes `themeRaw`.
    private func swatch(_ theme: Theme, _ label: String) -> some View {
        let selected = themeRaw == theme.rawValue
        return VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                swatchVisual(theme)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 1, y: 1)
                        .padding(.trailing, 5).padding(.bottom, 3)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11)
                .stroke(selected ? tokens.accent : .white.opacity(0.12), lineWidth: selected ? 2 : 1))
            Text(label).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(selected ? tokens.text : tokens.muted)
        }
        .contentShape(Rectangle())
        .onTapGesture { themeRaw = theme.rawValue }
    }

    /// The swatch fills, transcribed from the mockup's CSS gradients.
    @ViewBuilder private func swatchVisual(_ theme: Theme) -> some View {
        switch theme {
        case .system:   // sand / dark split on the diagonal
            LinearGradient(stops: [.init(color: Color(hex: 0xfbeede), location: 0),
                                   .init(color: Color(hex: 0xfbeede), location: 0.5),
                                   .init(color: Color(hex: 0x16181a), location: 0.5),
                                   .init(color: Color(hex: 0x16181a), location: 1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .sahar:    // sand → rose
            LinearGradient(colors: [Color(hex: 0xfbeede), Color(hex: 0xe7b7ab)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .noor:     // dark green-black
            RadialGradient(colors: [Color(hex: 0x1f2422), Color(hex: 0x0c0e0d)],
                           center: .top, startRadius: 0, endRadius: 60)
        case .layl:     // night sky + moon
            ZStack(alignment: .topTrailing) {
                RadialGradient(colors: [Color(hex: 0x26305a), Color(hex: 0x0a0b18)],
                               center: UnitPoint(x: 0.8, y: 0), startRadius: 0, endRadius: 70)
                Circle().fill(Color(hex: 0xf2cf7e)).frame(width: 14, height: 14).blur(radius: 0.5)
                    .padding(.top, 6).padding(.trailing, 8)
            }
        }
    }

    // MARK: - Rows

    private var hotkeyRow: some View {
        settingRow(icon: "playpause.fill", title: "Play / Pause", subtitle: "Global hotkey") {
            KeyboardShortcuts.Recorder(for: .togglePlay).controlSize(.small)
        }
    }

    private var mediaKeysRow: some View {
        settingRow(icon: "forward.fill", title: "Media keys", subtitle: "▶︎ ⏸ ⏭ & Control Center") {
            toggle($settings.mediaKeysEnabled)
        }
    }

    private var autoplayRow: some View {
        settingRow(icon: "play.circle.fill", title: "Autoplay next surah",
                   subtitle: "Continue through the reciter") {
            toggle($settings.autoplayEnabled)
        }
    }

    private var libraryFolderRow: some View {
        settingRow(icon: "folder.fill", title: "Library folder", subtitle: folderPath,
                   mono: true, topBorder: false) {
            HStack(spacing: 10) {
                linkButton("Change") { importer.chooseLibraryFolder(); folderRefresh += 1 }
                linkButton("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([importer.libraryFolderURL])
                }
            }
        }
    }

    private var autoImportRow: some View {
        settingRow(icon: "arrow.triangle.2.circlepath", title: "Auto-import from folder",
                   subtitle: "Watch & smart-tag new files") {
            toggle($settings.autoImportEnabled)
        }
    }

    private var launchAtLoginRow: some View {
        settingRow(icon: "power", title: "Launch at login",
                   subtitle: "Start quietly in the menubar", topBorder: false) {
            toggle(launchAtLogin)
        }
    }

    /// One settings row: a tinted icon tile, a title + subtitle, and a trailing control. `mono`
    /// renders the subtitle monospaced (the folder path); `topBorder` draws the hairline divider.
    private func settingRow<Trailing: View>(
        icon: String, title: String, subtitle: String, mono: Bool = false,
        topBorder: Bool = true, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(tokens.isDark ? 0.07 : 0.05))
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tokens.muted)
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(tokens.text)
                Text(subtitle)
                    .font(mono ? .system(size: 10.5, design: .monospaced) : .system(size: 10.5))
                    .foregroundStyle(tokens.muted).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .overlay(alignment: .top) { if topBorder { hairline(tokens.isDark ? 0.05 : 0.07) } }
    }

    // MARK: - About / attribution

    private var about: some View {
        VStack(spacing: 6) {
            MenuBarLabel(isPlaying: false, tint: tokens.accent)   // the equalizer mark
            Text("Qurani 1.0").font(.system(size: 12, weight: .semibold)).foregroundStyle(tokens.text)
            VStack(spacing: 2) {
                Text("Free Quran radio · macOS")
                Text("Audio: mp3quran · everyayah · quranicaudio · Quran.com")
                Text("Fonts: Amiri Quran · Noto Naskh Arabic (OFL)")
                Text("Live: Saudi & Egypt public broadcasts")
            }
            .font(.system(size: 9.5)).foregroundStyle(tokens.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
        .overlay(alignment: .top) { hairline(tokens.isDark ? 0.06 : 0.08) }
    }

    // MARK: - Small building blocks

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold)).tracking(1.3)
            .foregroundStyle(tokens.muted.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 9)
    }

    private func toggle(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding)
            .labelsHidden().toggleStyle(.switch).tint(tokens.accent).controlSize(.small)
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(tokens.gold)
        }
        .buttonStyle(.plain)
    }

    private func hairline(_ opacity: Double) -> some View {
        Rectangle().fill(Color.white.opacity(opacity)).frame(height: 1)
    }

    private var panelBackground: some View {
        ZStack {
            tokens.bg
            RadialGradient(colors: [tokens.accent.opacity(0.12), .clear],
                           center: .top, startRadius: 0, endRadius: 220).allowsHitTesting(false)
        }
    }

    // MARK: - Derived values

    /// The watched-folder path, tilde-abbreviated (`~/Music/Qurani`). Reads `folderRefresh` so a
    /// `Change` re-evaluates this after the importer updates its (unpublished) stored bookmark.
    private var folderPath: String {
        _ = folderRefresh
        return (importer.libraryFolderURL.path as NSString).abbreviatingWithTildeInPath
    }

    /// Reflects/sets the real `SMAppService` state. `register()` throws from unsigned / DerivedData
    /// builds — expected, so we swallow it and the toggle reverts on the next read. (Moved here from
    /// GlassPanel's old gear menu, now that Settings owns launch-at-login.)
    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { LoginItem.isEnabled },
            set: { on in
                do { try LoginItem.set(on) }
                catch { print("Qurani: launch-at-login change failed (expected when unsigned): \(error)") }
            }
        )
    }
}
