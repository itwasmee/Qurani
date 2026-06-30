import SwiftUI
import QuraniKit

/// The Mix surface — build state: assemble a pool of qaris (local 📚 + favorited/pooled on-demand
/// ☁︎), pick an order and a surah range, and start a random per-surah station. Each surah is then
/// played by a randomly-chosen pool member that actually contributes it (the assignment lives in
/// `MixEngine`; `AppModel` owns the live session).
///
/// Observes `catalog`/`favorites`/`pool`/`library` directly (derived from `model`) so the candidate
/// list and selection republish — `AppModel` does not forward its child stores' changes (same lesson
/// as Explore / Library). On-demand selection seeds from the persisted Mix pool; local selection is
/// session-scoped (the library has no persisted pool to seed from). `model.isMixing` swaps in a
/// placeholder until Task 5 fills the playing/queue UI.
struct MixTabView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var catalog: CatalogStore
    @ObservedObject var favorites: FavoritesStore
    @ObservedObject var pool: MixPoolStore
    @ObservedObject var library: LibraryStore
    let tokens: Tokens

    /// Local reciter names ticked into the pool (session-scoped — starts empty).
    @State private var selectedLocal: Set<String> = []
    /// On-demand reciter ids ticked into the pool, seeded from the persisted Mix pool.
    @State private var selectedOnDemand: Set<Int>
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
        self.tokens = tokens
        _selectedOnDemand = State(initialValue: model.pool.reciterIDs)
    }

    var body: some View {
        if model.isMixing {
            playingPlaceholder
        } else {
            buildBody
        }
    }

    // MARK: - Build

    private var buildBody: some View {
        VStack(spacing: 0) {
            mixHeader
            poolHeader
            if hasCandidates { poolList } else { emptyPool }
            controls
            startButton
        }
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

    // MARK: - Playing placeholder (Task 5 replaces this)

    private var playingPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "shuffle").font(.system(size: 26)).foregroundStyle(tokens.accent)
            Text("Mix playing").font(.system(size: 14, weight: .semibold)).foregroundStyle(tokens.text)
            Text("See the now-playing bar below").font(.system(size: 11)).foregroundStyle(tokens.muted)
            Button(action: { model.stopMix() }) {
                Text("Stop mix").font(.system(size: 11, weight: .semibold)).foregroundStyle(tokens.accent)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(tokens.accent.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity).frame(height: 300).padding()
    }

    // MARK: - Candidates + selection

    private var localCandidates: [String] { library.grouped().map(\.reciter) }

    private var onDemandCandidates: [Reciter] {
        catalog.reciters.filter { favorites.isFavorite(reciter: $0.id) || pool.contains($0.id) }
    }

    private var hasCandidates: Bool { !localCandidates.isEmpty || !onDemandCandidates.isEmpty }
    private var selectedCount: Int { selectedLocal.count + selectedOnDemand.count }
    private var selectionEmpty: Bool { selectedLocal.isEmpty && selectedOnDemand.isEmpty }

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

    private func toggleOnDemand(_ id: Int) {
        if selectedOnDemand.contains(id) { selectedOnDemand.remove(id) } else { selectedOnDemand.insert(id) }
    }

    private func toggleSelectAll() {
        if allSelected {
            selectedLocal.removeAll(); selectedOnDemand.removeAll()
        } else {
            selectedLocal = Set(localCandidates)
            selectedOnDemand = Set(onDemandCandidates.map(\.id))
        }
    }

    private func start() {
        let config = MixConfig(order: order, range: resolvedRange)
        let builtPool = model.buildPool(onDemandIDs: selectedOnDemand, localNames: selectedLocal)
        model.startMix(config: config, pool: builtPool)
    }
}
