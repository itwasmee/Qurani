import SwiftUI
import QuraniKit

/// The Mix surface — build state: assemble a pool of qaris (local 📚 + favorited/pooled on-demand
/// ☁︎), pick an order and a surah range, and start a random per-surah station. Each surah is then
/// played by a randomly-chosen pool member that actually contributes it (the assignment lives in
/// `MixEngine`; `AppModel` owns the live session).
///
/// Observes `catalog`/`favorites`/`pool`/`library` directly (derived from `model`) so the candidate
/// list republishes — `AppModel` does not forward its child stores' changes (same lesson as Explore /
/// Library). **Selection here is per-session, not persisted.** Both the ☁︎ on-demand picks
/// (`selectedOnDemand`) and the 📚 local picks (`selectedLocal`) live in view `@State`; the on-demand
/// set is *seeded* in `init` from the persisted `MixPoolStore` each time the tab opens, so the user's
/// curated pool shows pre-selected. Ticking, "Clear", and "Select all" mutate only that session state
/// — they do NOT write back to `MixPoolStore`, so a bulk "Clear" can't wipe the saved pool. The pool
/// is curated from Explore's "+ Mix pool"; this tab just selects from it for one run. Phantom entries
/// (a seeded id the catalog no longer lists, or a local name whose files were removed) are reconciled
/// away before the POOL count / build. `model.isMixing` swaps in the playing/queue UI.
struct MixTabView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var favorites: FavoritesStore
    @ObservedObject var pool: MixPoolStore
    @ObservedObject var library: LibraryStore
    let tokens: Tokens

    /// Local reciter names ticked for this session (📚 — starts empty; v1 has no persisted local pool).
    @State private var selectedLocal: Set<String> = []
    /// On-demand reciter ids ticked for this session (☁︎). Seeded in `init` from the persisted
    /// `model.pool` so the curated pool shows pre-selected, then mutated only in `@State` — never
    /// written back, so "Clear" / "Select all" can't mutate the saved pool.
    @State private var selectedOnDemand: Set<Int> = []
    @State private var order: MixConfig.Order = .shuffle
    @State private var rangeMode: RangeMode = .full
    @State private var juz = 1
    @State private var customStart = 1
    @State private var customEnd = 114

    /// The RANGE chip selection; `.juz`/`.custom` reveal a minimal stepper control and map to the
    /// engine's `MixConfig.Range` at start.
    private enum RangeMode { case full, juz, custom }

    init(model: AppModel, tokens: Tokens) {
        _model = ObservedObject(wrappedValue: model)
        _catalog = ObservedObject(wrappedValue: model.catalog)
        _favorites = ObservedObject(wrappedValue: model.favorites)
        _pool = ObservedObject(wrappedValue: model.pool)
        _library = ObservedObject(wrappedValue: model.library)
        // Seed the session on-demand selection from the persisted pool. SwiftUI honors a `@State`
        // initial value once per view identity, so this re-seeds each time the Mix tab is (re)opened.
        _selectedOnDemand = State(initialValue: model.pool.reciterIDs)
        self.tokens = tokens
    }

    var body: some View {
        Group {
            if model.isMixing {
                playingBody
            } else {
                buildBody
            }
        }
        // Drop a stale "no surahs in range" hint when leaving the Mix tab, so reopening it later never
        // shows a no-coverage warning left over from a prior failed build (it's cleared on next start).
        .onDisappear { model.mixNoCoverage = false }
    }

    // MARK: - Build

    private var buildBody: some View {
        VStack(spacing: 0) {
            mixHeader
            poolHeader
            if hasCandidates { poolList } else { emptyPool }
            controls
            if model.mixNoCoverage { noCoverageHint }
            startButton
        }
    }

    /// Shown when a non-empty selection built an empty queue (`AppModel.mixNoCoverage`): the chosen
    /// range has no surah any selected reciter covers. A hint, not a teardown — current audio plays on.
    private var noCoverageHint: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
            Text("No surahs in range for this pool").font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity)
        .padding(.top, 9).padding(.horizontal, 14)
    }

    private var mixHeader: some View {
        VStack(spacing: 2) {
            Text("Random Mix").font(.system(size: 17, weight: .bold)).foregroundStyle(tokens.text)
            Text("A different qari each surah").font(.system(size: 11)).foregroundStyle(tokens.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2).padding(.bottom, 10)
    }

    // MARK: - Pool

    private var poolHeader: some View {
        HStack {
            Text(selectedCount > 0 ? "POOL · \(selectedCount) SELECTED" : "POOL")
                .font(.system(size: 9.5, weight: .bold)).tracking(1.4)
            Spacer()
            if hasCandidates {
                Button(action: toggleSelectAll) {
                    Text(allSelected ? "Clear" : "Select all")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(tokens.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(tokens.muted)
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 5)
    }

    private var poolList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(localCandidates, id: \.self) { name in
                    PoolRow(name: name, source: .local, selected: selectedLocal.contains(name),
                            tokens: tokens) { toggleLocal(name) }
                }
                ForEach(onDemandCandidates) { r in
                    PoolRow(name: r.name, source: .onDemand, selected: selectedOnDemand.contains(r.id),
                            tokens: tokens) { toggleOnDemand(r.id) }
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(maxHeight: 196)
    }

    private var emptyPool: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.2").font(.system(size: 20)).foregroundStyle(tokens.muted)
            Text("No reciters yet").font(.system(size: 12, weight: .semibold)).foregroundStyle(tokens.text)
            Text("Favorite reciters in Explore or add files in Library")
                .font(.system(size: 10.5)).foregroundStyle(tokens.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28).padding(.horizontal, 24)
    }

    // MARK: - Controls (order + range)

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("SURAH ORDER")
            orderSegment.padding(.bottom, 11)
            sectionLabel("RANGE")
            rangeChips
            rangeDetail
        }
        .padding(.horizontal, 14).padding(.top, 6)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 9.5, weight: .bold)).tracking(1)
            .foregroundStyle(tokens.muted).padding(.bottom, 6)
    }

    private var orderSegment: some View {
        HStack(spacing: 4) {
            segButton("In order (1→114)", on: order == .inOrder) { order = .inOrder }
            segButton("Shuffle", on: order == .shuffle) { order = .shuffle }
        }
        .padding(3)
        .background(Color.white.opacity(tokens.isDark ? 0.05 : 0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func segButton(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? tokens.accent : tokens.muted)
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(on ? tokens.accent.opacity(0.16) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var rangeChips: some View {
        HStack(spacing: 6) {
            FilterChip(text: "Full Qur'an", on: rangeMode == .full, tokens: tokens) { rangeMode = .full }
            FilterChip(text: "By Juz'", on: rangeMode == .juz, tokens: tokens) { rangeMode = .juz }
            FilterChip(text: "Custom", on: rangeMode == .custom, tokens: tokens) { rangeMode = .custom }
        }
    }

    @ViewBuilder private var rangeDetail: some View {
        switch rangeMode {
        case .full:
            EmptyView()
        case .juz:
            Stepper("Juz' \(juz)", value: $juz, in: 1...30)
                .font(.system(size: 11)).foregroundStyle(tokens.text).padding(.top, 8)
        case .custom:
            HStack(spacing: 12) {
                Stepper("From \(customStart)", value: $customStart, in: 1...114)
                Stepper("To \(customEnd)", value: $customEnd, in: 1...114)
            }
            .font(.system(size: 11)).foregroundStyle(tokens.text).padding(.top, 8)
        }
    }

    // MARK: - Start

    private var startButton: some View {
        Button(action: start) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill").font(.system(size: 12, weight: .bold))
                Text("Start Random Mix").font(.system(size: 13.5, weight: .bold))
            }
            .foregroundStyle(onAccent)
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(tokens.accent.opacity(selectionEmpty ? 0.35 : 1),
                        in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .disabled(selectionEmpty)
        .padding(.horizontal, 13).padding(.vertical, 14)
    }

    // MARK: - Playing (queue)
    //
    // The mockup's right panel: a header labelling the running station (order + qari count + range)
    // with a Re-roll chip, then the resolved `mixQueue` as a scrollable list — each row a Style-B
    // `SurahNameView` (medallion + Amiri name + the assigned reciter on the subtitle line) with a
    // compact source badge, the item at `mixIndex` highlighted with the equalizer. There's no in-tab
    // Stop control (the mockup has none); an explicit play elsewhere ends the session (see AppModel).

    private var playingBody: some View {
        VStack(spacing: 0) {
            playingHeader
            queueList
        }
    }

    private var playingHeader: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Random Mix · \(orderLabel)")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(tokens.text)
                Text("\(qariCount) qaris · \(rangeLabel)")
                    .font(.system(size: 10)).foregroundStyle(tokens.muted)
            }
            Spacer(minLength: 6)
            rerollButton
        }
        .padding(.horizontal, 13).padding(.top, 6).padding(.bottom, 8)
    }

    private var rerollButton: some View {
        Button(action: { model.rerollMix() }) {
            HStack(spacing: 6) {
                Image(systemName: "dice").font(.system(size: 12, weight: .semibold))
                Text("Re-roll").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(tokens.accent)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(tokens.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help("Re-roll — reshuffle the surah order and the reciter assigned to each surah")
    }

    private var queueList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(model.mixQueue.enumerated()), id: \.element.id) { index, item in
                    queueRow(item, playing: index == model.mixIndex)
                }
            }
            .padding(.horizontal, 8).padding(.bottom, 6)
        }
        .frame(height: 300)
    }

    private func queueRow(_ item: MixQueueItem, playing: Bool) -> some View {
        let surah = model.surahs.first { $0.number == item.surah }
        let member = model.mixMember(item.memberID)
        return HStack(spacing: 6) {
            SurahNameView(number: item.surah,
                          nameAr: surah?.nameAr ?? "Surah \(item.surah)",
                          translit: member?.displayName ?? item.memberID,
                          tokens: tokens, playing: playing)
            sourceBadge(member?.source)
        }
        .padding(.vertical, 6).padding(.horizontal, 9)
        .background(playing ? tokens.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(tokens.accent.opacity(playing ? 0.22 : 0), lineWidth: 1))
    }

    /// Compact source chip on a queue row: 📚 (local) or ☁︎ (on-demand). The mockup uses the bare
    /// glyph here (vs. the build view's labelled "📚 LOCAL" / "☁︎ ON-DEMAND" `PoolRow` badge) to keep
    /// the dense list legible; the gold / blue tints match `PoolRow`.
    @ViewBuilder private func sourceBadge(_ source: PoolSource?) -> some View {
        if let source {
            let isLocal = source == .local
            // Tint the glyph to match the build view's `PoolRow` badge: ☁︎ is a text glyph that needs an
            // explicit color (it was inheriting the primary text color), so gold for local / blue for
            // on-demand keeps the queue badge consistent with the pool list. (📚 is emoji, ignores it.)
            let fg = isLocal ? tokens.gold : (tokens.isDark ? Color(hex: 0x9fd0f0) : Color(hex: 0x2c6e96))
            Text(isLocal ? "📚" : "☁︎")
                .font(.system(size: 10))
                .foregroundStyle(fg)
                .padding(.horizontal, 5).padding(.vertical, 3)
                .background((isLocal ? tokens.gold : Color(hex: 0x78c8ff)).opacity(tokens.isDark ? 0.16 : 0.20),
                            in: RoundedRectangle(cornerRadius: 5))
                .fixedSize()
        }
    }

    private var orderLabel: String {
        switch model.mixConfig.order {
        case .inOrder: return "In order"
        case .shuffle: return "Shuffle"
        }
    }

    private var rangeLabel: String {
        switch model.mixConfig.range {
        case .full: return "full Qur'an"
        case .juz(let n): return "Juz' \(n)"
        case .custom(let r): return "Surah \(r.lowerBound)–\(r.upperBound)"
        }
    }

    /// Distinct reciters featured across the current queue (the "N qaris" subtitle count).
    private var qariCount: Int { Set(model.mixQueue.map(\.memberID)).count }

    // MARK: - Candidates + selection

    private var localCandidates: [String] { library.grouped().map(\.reciter) }

    private var onDemandCandidates: [Reciter] {
        catalog.reciters.filter { favorites.isFavorite(reciter: $0.id) || pool.contains($0.id) }
    }

    private var hasCandidates: Bool { !localCandidates.isEmpty || !onDemandCandidates.isEmpty }

    /// The session on-demand selection reconciled against the loaded catalog — a seeded id whose
    /// reciter the catalog no longer lists (reshaped, or not yet loaded) is a phantom, dropped so
    /// neither the POOL count nor the built pool references a vanished reciter.
    private var validOnDemand: Set<Int> { selectedOnDemand.intersection(catalog.reciters.map(\.id)) }
    /// Session-picked local names reconciled against the current library groups — a name whose files
    /// have all been removed since it was ticked is dropped likewise.
    private var validLocal: Set<String> { selectedLocal.intersection(localCandidates) }

    private var selectedCount: Int { validLocal.count + validOnDemand.count }
    private var selectionEmpty: Bool { validLocal.isEmpty && validOnDemand.isEmpty }

    private var allSelected: Bool {
        hasCandidates
            && localCandidates.allSatisfy(selectedLocal.contains)
            && onDemandCandidates.allSatisfy { selectedOnDemand.contains($0.id) }
    }

    private var onAccent: Color { tokens.isDark ? Color(hex: 0x05291f) : .white }

    private var resolvedRange: MixConfig.Range {
        switch rangeMode {
        case .full: return .full
        case .juz: return .juz(juz)
        case .custom: return .custom(min(customStart, customEnd)...max(customStart, customEnd))
        }
    }

    private func toggleLocal(_ name: String) {
        if selectedLocal.contains(name) { selectedLocal.remove(name) } else { selectedLocal.insert(name) }
    }

    /// Tick / untick an on-demand reciter for this session only — mutates `@State`, never the
    /// persisted pool (curated from Explore). So selecting here can't edit the user's saved pool.
    private func toggleOnDemand(_ id: Int) {
        if selectedOnDemand.contains(id) { selectedOnDemand.remove(id) } else { selectedOnDemand.insert(id) }
    }

    /// "Clear" / "Select all" — flips every candidate's session selection. Mutates only `@State`
    /// (never the persisted pool), so a bulk "Clear" is non-destructive to the saved pool.
    private func toggleSelectAll() {
        if allSelected {
            selectedLocal.removeAll()
            selectedOnDemand.removeAll()
        } else {
            selectedLocal = Set(localCandidates)
            selectedOnDemand = Set(onDemandCandidates.map(\.id))
        }
    }

    private func start() {
        let config = MixConfig(order: order, range: resolvedRange)
        let builtPool = model.buildPool(onDemandIDs: validOnDemand, localNames: validLocal)
        model.startMix(config: config, pool: builtPool)
    }
}
