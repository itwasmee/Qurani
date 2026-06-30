import SwiftUI
import QuraniKit

/// The Task 7 tagger review surface: presented (as a full-panel overlay) whenever the importer has
/// `pendingImports` awaiting confirmation. Each pending file shows its smart-tag guess — an editable
/// reciter name, a surah picker, and a confidence chip (✓ high / ~ low) — and **Add N to Library**
/// commits the whole batch to the library.
///
/// Editing lives in a local `[UUID: RowEdit]` keyed by the pending id, seeded lazily from each
/// `guess` (so `PendingImport`, the importer's source of truth, is never mutated, and rows added
/// while the sheet is open — e.g. by the watched folder — pick up their guess automatically).
/// Observes `importer` directly so that live list republishes, mirroring the other tab views.
///
/// Design choices (documented per the brief):
///   • **Add is disabled until every row is valid** (non-empty reciter + a chosen surah), matching
///     the mockup subtitle "Fix any amber field, then add." — predictable and avoids silently
///     dropping rows. `commitImports` then clears all committed pending ids, so the overlay closes.
///   • **Cancel discards the entire pending batch.** The overlay's presence is driven solely by
///     `pendingImports` being non-empty, so a dismiss must empty the list (otherwise it re-presents).
///   • **Amber highlight** = current reciter empty OR the guess's `confidence < 0.5` (advisory "needs
///     review"); the **confidence chip** is the static `guess.confidence` (✓ ≥ 0.8, else ~). Amber is
///     advisory only — it does not block Add (a low-confidence row with a reciter + surah is valid).
///   • "Amber" maps to the theme-adaptive `tokens.gold` token (Noor #e7c46a ≈ the mockup's #e7b865).
struct TaggerReviewView: View {
    @ObservedObject var importer: LibraryImporter
    let surahs: [Surah]
    let tokens: Tokens
    /// Commit the confirmed rows → `AppModel.commitImports` → `library.add`. Injected (mirrors
    /// GlassPanel's `play` / `playLocal`) so this view never reaches into AppModel directly.
    let commit: ([ReviewedImport]) -> Void

    /// One row's edited state. Absent from `edits` == "still showing the guess".
    private struct RowEdit { var reciter: String; var surah: Int? }
    @State private var edits: [UUID: RowEdit] = [:]

    /// number → Surah, memoized for the picker labels + the selected-surah name lookup.
    private let surahsByNumber: [Int: Surah]

    init(importer: LibraryImporter, surahs: [Surah], tokens: Tokens,
         commit: @escaping ([ReviewedImport]) -> Void) {
        _importer = ObservedObject(wrappedValue: importer)
        self.surahs = surahs
        self.surahsByNumber = Dictionary(surahs.map { ($0.number, $0) }, uniquingKeysWith: { a, _ in a })
        self.tokens = tokens
        self.commit = commit
    }

    private var pending: [PendingImport] { importer.pendingImports }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(pending) { row($0) }
                }
                .padding(.top, 2).padding(.bottom, 8)
            }
            .frame(maxHeight: .infinity)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(panelBackground)
    }

    // MARK: - Header / subtitle

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.seal").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tokens.accent)
                Text("Review \(pending.count) import\(pending.count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(tokens.text)
                Spacer(minLength: 0)
            }
            Text("Auto-detected from filename, folder & tags. Fix any amber field, then add.")
                .font(.system(size: 10.5)).foregroundStyle(tokens.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.top, 13).padding(.bottom, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Row

    private func row(_ p: PendingImport) -> some View {
        let amber = isAmber(p)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: amber ? "exclamationmark.triangle" : "doc")
                    .font(.system(size: 10)).foregroundStyle(amber ? tokens.gold : tokens.muted)
                Text(amber ? "\(p.url.lastPathComponent) · needs review" : p.url.lastPathComponent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(amber ? tokens.gold : tokens.muted)
                    .lineLimit(1).truncationMode(.middle)
            }
            HStack(spacing: 7) {
                reciterField(p)
                surahField(p)
            }
        }
        .padding(10)
        .background(amber ? tokens.gold.opacity(0.07) : Color.white.opacity(tokens.isDark ? 0.04 : 0.03),
                    in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13)
            .stroke(amber ? tokens.gold.opacity(0.40) : Color.white.opacity(tokens.isDark ? 0.06 : 0.22),
                    lineWidth: 1))
        .padding(.horizontal, 9)
    }

    /// Editable reciter name. Amber placeholder while empty; the confidence chip shows once filled.
    private func reciterField(_ p: PendingImport) -> some View {
        field(label: "Reciter") {
            TextField("Pick reciter…", text: reciterBinding(p))
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(currentReciter(p).isEmpty ? tokens.gold : tokens.text)
        } trailing: {
            if !currentReciter(p).isEmpty { confidenceChip(p) }
        }
    }

    /// Surah picker over the 114 surahs (a borderless `Menu`, styled to sit inside the field). Shows
    /// the selected surah's Amiri Arabic name, or an amber "Pick surah…" + chevron when none is set.
    private func surahField(_ p: PendingImport) -> some View {
        let selected = currentSurah(p)
        return field(label: "Surah") {
            Menu {
                ForEach(surahs) { s in
                    Button { setSurah(p, s.number) } label: {
                        Text("\(s.number) · \(s.translit) · \(s.nameAr)")
                    }
                }
            } label: {
                Text(selected.flatMap { surahsByNumber[$0]?.nameAr } ?? (selected.map { "Surah \($0)" } ?? "Pick surah…"))
                    .font(selected == nil ? .system(size: 11.5) : .custom("Amiri Quran", size: 15))
                    .foregroundStyle(selected == nil ? tokens.gold : tokens.text)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        } trailing: {
            if selected == nil {
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tokens.muted)
            } else {
                confidenceChip(p)
            }
        }
    }

    /// One field box: an uppercase caption over an editable control, plus an optional trailing badge.
    private func field<Content: View, Trailing: View>(
        label: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .bold)).tracking(0.6)
                    .foregroundStyle(tokens.muted.opacity(0.9))
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(tokens.isDark ? 0.06 : 0.04), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .stroke(Color.white.opacity(tokens.isDark ? 0.08 : 0.28), lineWidth: 1))
    }

    /// ✓ (accent) when the guess was confident (≥ 0.8), else ~ (gold/amber).
    private func confidenceChip(_ p: PendingImport) -> some View {
        let ok = p.guess.confidence >= 0.8
        let tint = ok ? tokens.accent : tokens.gold
        return Text(ok ? "✓" : "~")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(tint)
            .frame(width: 15, height: 15)
            .background(tint.opacity(0.20), in: Circle())
    }

    // MARK: - Footer (Cancel · Add N to Library)

    private var footer: some View {
        HStack(spacing: 9) {
            Button(action: cancel) {
                Text("Cancel").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tokens.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(tokens.glassTint, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(tokens.isDark ? 0.08 : 0.30), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Discard these imports")

            Button(action: add) {
                Text("Add \(pending.count) to Library").font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(allValid ? Color(hex: 0x05312a) : tokens.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(allValid ? tokens.accent : tokens.accent.opacity(0.18),
                                in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!allValid)
            .help(allValid ? "Add these files to the library" : "Fill in every reciter and surah first")
        }
        .padding(.horizontal, 11).padding(.top, 4).padding(.bottom, 12)
    }

    private var panelBackground: some View {
        ZStack {
            tokens.bg
            RadialGradient(colors: [tokens.accent.opacity(0.12), .clear],
                           center: .top, startRadius: 0, endRadius: 220)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Editing state

    /// Current edit for a row, falling back to the smart-tag guess when untouched.
    private func edit(_ p: PendingImport) -> RowEdit {
        edits[p.id] ?? RowEdit(reciter: p.guess.reciterName ?? "", surah: p.guess.surahNumber)
    }

    private func currentReciter(_ p: PendingImport) -> String { edit(p).reciter }
    private func currentSurah(_ p: PendingImport) -> Int? { edit(p).surah }

    private func reciterBinding(_ p: PendingImport) -> Binding<String> {
        Binding(get: { edit(p).reciter },
                set: { var e = edit(p); e.reciter = $0; edits[p.id] = e })
    }

    private func setSurah(_ p: PendingImport, _ n: Int) {
        var e = edit(p); e.surah = n; edits[p.id] = e
    }

    /// A row is valid (committable) once it has a non-empty reciter and a chosen surah.
    private func isValid(_ p: PendingImport) -> Bool {
        !trimmed(edit(p).reciter).isEmpty && edit(p).surah != nil
    }

    private var allValid: Bool { !pending.isEmpty && pending.allSatisfy(isValid) }

    /// Advisory "needs review" highlight: an empty reciter, or a low-confidence guess.
    private func isAmber(_ p: PendingImport) -> Bool {
        trimmed(edit(p).reciter).isEmpty || p.guess.confidence < 0.5
    }

    private func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Actions

    private func add() {
        let reviewed = pending.compactMap { p -> ReviewedImport? in
            let name = trimmed(edit(p).reciter)
            guard !name.isEmpty, let surah = edit(p).surah else { return nil }
            return ReviewedImport(pendingID: p.id, reciterName: name, surahNumber: surah)
        }
        commit(reviewed)
        edits.removeAll()   // committed ids drop from pending; clear any stale edits
    }

    private func cancel() {
        importer.clearPending(ids: Set(pending.map(\.id)))
        edits.removeAll()
    }
}
