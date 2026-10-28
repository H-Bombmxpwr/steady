import SwiftUI

struct StudioShopView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case gear = "Gear", promo = "Promo", records = "Records", buddy = "Buddy"
        var id: String { rawValue }
    }

    let plan: Plan
    let targets: DailyTargets
    @State var tab: Tab
    @Environment(\.dismiss) private var dismiss

    private var store: BuddyStore { .shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StudioScene(store: store, mood: .content,
                                health: BuddyHealth(score: store.state.health), height: 210)
                    Picker("Section", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch tab {
                    case .gear: GearShop(plan: plan, targets: targets)
                    case .promo: PromoView(plan: plan, targets: targets)
                    case .records: CrateView(plan: plan, targets: targets)
                    case .buddy: BuddyEditor(plan: plan, targets: targets)
                    }

                    Text("Art: Microsoft Fluent Emoji (MIT). Album art and previews courtesy of Apple Music.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding()
            }
            .brandBackground()
            .navigationTitle("\(store.state.name)'s Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { NotesBadge(notes: store.notes).fixedSize() }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .themedRoot()
    }
}

// MARK: - Gear

private struct GearShop: View {
    let plan: Plan
    let targets: DailyTargets
    private var store: BuddyStore { .shared }
    @State private var failed: String?

    var body: some View {
        let owned = Set(store.state.owned)
        VStack(alignment: .leading, spacing: 18) {
            if let deal = StudioCatalog.dailyDeal(owned: owned, progress: store.progress) {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("Today's pick · 40% off")
                    GearRow(gear: deal.gear, price: deal.price, plan: plan, failed: $failed)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.warn.opacity(0.12)))
                }
            }
            if let failed {
                Text(failed).font(.footnote).foregroundStyle(Theme.danger)
            }
            ForEach(StudioSlot.allCases) { slot in
                let items = StudioCatalog.all.filter { $0.slot == slot } +
                    (slot == .shelf && owned.contains(StudioCatalog.trophy.id) ? [StudioCatalog.trophy] : [])
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        sectionTitle(slot.label)
                        Spacer()
                        if slot != .wallpaper, slot != .floor, store.placed(in: slot) != nil {
                            Button("Clear") { store.clear(slot) }
                                .font(.caption).tint(Theme.textDim)
                        }
                    }
                    ForEach(items) { gear in
                        GearRow(gear: gear, price: StudioCatalog.price(gear), plan: plan, failed: $failed)
                    }
                }
            }
        }
    }
}

private struct GearRow: View {
    let gear: Gear
    let price: Double
    let plan: Plan
    @Binding var failed: String?
    private var store: BuddyStore { .shared }

    var body: some View {
        let owned = store.owns(gear)
        let placed = store.placed(in: gear.slot)?.id == gear.id
        let locked = !owned && (gear.exclusive || !store.isUnlocked(gear))
        HStack(spacing: 12) {
            Group {
                if let asset = gear.asset {
                    Sprite(asset, size: 40)
                } else if let c = gear.colors {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [Color(hex: c.0), Color(hex: c.1)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 40, height: 40)
                }
            }
            .opacity(locked ? 0.35 : 1)
            .overlay(alignment: .bottomTrailing) {
                if locked {
                    Image(systemName: "lock.fill").font(.caption2.bold()).foregroundStyle(Theme.textDim)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(gear.name).font(.subheadline.bold())
                Text(gear.blurb).font(.caption).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if placed {
                Text("In room").font(.caption.bold()).foregroundStyle(Theme.accent)
            } else if owned {
                Button("Place") { Haptics.selection(); withAnimation(.spring) { store.place(gear) } }
                    .buttonStyle(.bordered).tint(Theme.accent).font(.caption.bold())
            } else if let track = gear.track {
                Text("Track \(track)").font(.caption.bold()).foregroundStyle(Theme.textDim)
            } else if gear.id == StudioCatalog.trophy.id {
                Text("Goal").font(.caption.bold()).foregroundStyle(Theme.textDim)
            } else if locked {
                // Gated by weight, not by notes: it opens when the trend gets there.
                VStack(alignment: .trailing, spacing: 1) {
                    Text("at \(lb(IdleEngine.unlockWeight(StudioCatalog.unlockAt(gear), plan: plan))) lb")
                        .font(.caption.bold()).foregroundStyle(Theme.textDim)
                    Text(IdleEngine.format(price)).font(.caption2).foregroundStyle(Theme.textDim)
                }
            } else {
                Button {
                    if withAnimation(.spring, { store.buy(gear, price: price) }) {
                        Haptics.success()
                        failed = nil
                    } else {
                        failed = "Not enough notes yet — collect the jar, or buy some promo to earn faster."
                    }
                } label: {
                    HStack(spacing: 3) {
                        Sprite("musical_note", size: 13)
                        Text(IdleEngine.format(price)).monospacedDigit()
                    }
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).font(.caption.bold())
            }
        }
    }
}

private func lb(_ x: Double) -> String { x.formatted(.number.precision(.fractionLength(1))) }

// MARK: - Promo

/// The idle game proper: generators that pay notes per second, every copy 15%
/// dearer than the last, unlocked — and capped — by progress toward the goal.
/// The multipliers are shown in full, because the point is that you can see
/// which of them is yours to move.
private struct PromoView: View {
    let plan: Plan
    let targets: DailyTargets
    private var store: BuddyStore { .shared }
    @State private var failed: String?

    var body: some View {
        let m = store.multipliers(plan: plan, targets: targets)
        let rate = store.rate(plan: plan, targets: targets)
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    sectionTitle("Earning")
                    Spacer()
                    Text("\(IdleEngine.format(rate))/s").font(.headline).monospacedDigit()
                }
                multiplierRow("chart_increasing", "Progress to goal",
                              "\(Int(store.progress * 100))% of the way · ×20 at the goal, ×40 once you're there", m.progress)
                multiplierRow(BuddyHealth(score: store.state.health).sprite, "Health",
                              "From the food you've logged this week · ×0.5 to ×1.5", m.health)
                multiplierRow("musical_note", "Hype",
                              "+5% per sound-check item today · resets at midnight", m.hype)
                multiplierRow("sparkles", "Collection",
                              "+3% per piece of gear, +10% per bandmate", m.collection)
                Text("Generators unlock as your trend weight gets closer to the goal, and each one caps at \(store.levelCap) copies for now — \(Generator.levelCap(progress: 1)) at the goal. If the scale stops moving, so does the studio.")
                    .font(.caption).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let failed { Text(failed).font(.footnote).foregroundStyle(Theme.danger) }

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Promo")
                ForEach(IdleEngine.generators) { g in
                    generatorRow(g, multiplier: m.total)
                }
            }
        }
    }

    private func multiplierRow(_ sprite: String, _ title: String, _ detail: String, _ value: Double) -> some View {
        HStack(spacing: 10) {
            Sprite(sprite, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text("×\(value < 10 ? String(format: "%.2f", value) : IdleEngine.format(value))")
                .font(.subheadline.bold()).monospacedDigit()
                .foregroundStyle(value < 1 ? Theme.danger : Theme.accent)
        }
    }

    private func generatorRow(_ g: Generator, multiplier: Double) -> some View {
        let level = store.level(g)
        let unlocked = store.isUnlocked(g)
        let capped = level >= store.levelCap
        let cost = g.cost(level: level)
        return HStack(spacing: 12) {
            Sprite(g.sprite, size: 40)
                .opacity(unlocked ? 1 : 0.35)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(g.name).font(.subheadline.bold())
                    if level > 0 {
                        Text("×\(level)").font(.caption.bold()).foregroundStyle(Theme.accent)
                    }
                }
                Text(unlocked
                     ? "+\(IdleEngine.format(g.baseRate * multiplier))/s each · \(g.blurb)"
                     : g.blurb)
                    .font(.caption).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if !unlocked {
                Text("at \(lb(IdleEngine.unlockWeight(g.unlockAt, plan: plan))) lb")
                    .font(.caption.bold()).foregroundStyle(Theme.textDim)
            } else if capped {
                Text("Max for now").font(.caption.bold()).foregroundStyle(Theme.textDim)
            } else {
                Button {
                    if withAnimation(.spring, { store.buy(g, plan: plan, targets: targets) }) {
                        Haptics.success()
                        failed = nil
                    } else {
                        failed = "Not enough notes yet — collect the jar first."
                    }
                } label: {
                    HStack(spacing: 3) {
                        Sprite("musical_note", size: 13)
                        Text(IdleEngine.format(cost)).monospacedDigit()
                    }
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).font(.caption.bold())
            }
        }
    }
}

private func sectionTitle(_ text: String) -> some View {
    Text(text.uppercased())
        .font(.caption.bold()).kerning(1.2)
        .foregroundStyle(Theme.textDim)
}

// MARK: - Records

private struct CrateView: View {
    let plan: Plan
    let targets: DailyTargets
    private var store: BuddyStore { .shared }
    private var spotify: SpotifyLink { .shared }
    @State private var searching = false
    @State private var revealed: CollectedRecord?
    @State private var failed: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            digs
            crate
            buyRecord
            SpotifySection()
        }
        .sheet(isPresented: $searching) {
            RecordSearchView()
        }
        .sheet(item: $revealed) { record in
            RecordReveal(record: record)
                .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private var digs: some View {
        let count = store.state.digs
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(count > 0 ? "\(count) record\(count == 1 ? "" : "s") to claim" : "How records are earned")
            if count > 0 {
                if spotify.isLinked, !store.state.spotifyQueue.isEmpty {
                    Button {
                        if let r = store.revealNextFromSpotify() {
                            Haptics.success()
                            revealed = r
                        }
                    } label: {
                        Label("Reveal from your Spotify", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Color(hex: 0x1DB954))
                    Text("Least-played first. Your most-played album is saved for finishing the tour.")
                        .font(.caption).foregroundStyle(Theme.textDim)
                }
                Button {
                    searching = true
                } label: {
                    Label("Pick any album", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(Theme.accent)
            } else {
                Text("Every new 1 lb low on your trend weight earns a record. Every 5 lb finishes a track and earns studio gear. Weigh in daily — the trend can only find new lows if it sees you.")
                    .font(.footnote).foregroundStyle(Theme.textDim)
            }
        }
    }

    private var crate: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("The crate · \(store.state.records.count)")
            if store.state.records.isEmpty {
                Text("Empty for now. The first pound off the trend changes that.")
                    .font(.footnote).foregroundStyle(Theme.textDim)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 14) {
                    ForEach(store.state.records.reversed()) { record in
                        RecordTile(record: record)
                    }
                }
            }
        }
    }

    private var buyRecord: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if store.buyRecord(rate: store.rate(plan: plan, targets: targets)) {
                    Haptics.success()
                    failed = nil
                } else {
                    failed = "Not enough notes yet."
                }
            } label: {
                HStack {
                    Text("Buy a record dig")
                    Spacer()
                    Sprite("musical_note", size: 14)
                    Text(IdleEngine.format(store.recordPrice(rate: store.rate(plan: plan, targets: targets)))).monospacedDigit()
                }
            }
            .buttonStyle(.bordered).tint(Theme.accent)
            if let failed { Text(failed).font(.caption).foregroundStyle(Theme.danger) }
        }
    }
}

private struct RecordTile: View {
    let record: CollectedRecord
    private var player: RecordPlayer { .shared }

    var body: some View {
        let playing = player.playingID == record.id
        let loading = player.loadingID == record.id
        Button {
            Haptics.tap()
            player.toggle(record)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    RecordSleeve(record: record, size: 96)
                    if playing || loading {
                        Circle().fill(.black.opacity(0.55)).frame(width: 36)
                        if loading { ProgressView().tint(.white) }
                        else { Image(systemName: "stop.fill").foregroundStyle(.white) }
                    }
                }
                Text(record.title).font(.caption.bold()).lineLimit(1)
                Text(record.artist).font(.caption2).foregroundStyle(Theme.textDim).lineLimit(1)
                Text(record.reason).font(.caption2).foregroundStyle(Theme.accent).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let link = record.spotifyURL, let url = URL(string: link) {
                Link(destination: url) { Label("Open in Spotify", systemImage: "arrow.up.right") }
            }
        }
    }
}

/// The moment a record comes out of the sleeve.
private struct RecordReveal: View {
    let record: CollectedRecord
    @State private var out = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                VinylDisc(record: record, size: 170, spinning: out)
                    .offset(x: out ? 60 : 0)
                RecordSleeve(record: record, size: 180)
                    .offset(x: out ? -40 : 0)
            }
            .frame(height: 200)
            VStack(spacing: 4) {
                Text(record.title).font(.title3.bold()).multilineTextAlignment(.center)
                Text(record.artist).foregroundStyle(Theme.textDim)
            }
            Button {
                RecordPlayer.shared.toggle(record)
            } label: {
                Label("Spin it", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent)
        }
        .padding()
        .overlay { ConfettiView() }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.3)) { out = true }
        }
    }
}

// MARK: - Search

struct RecordSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var term = ""
    @State private var results: [CollectedRecord] = []
    @State private var loading = false
    @State private var error: String?
    @State private var claimed: CollectedRecord?
    private var store: BuddyStore { .shared }

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Text(error).font(.footnote).foregroundStyle(Theme.danger)
                }
                ForEach(results) { record in
                    let have = store.state.records.contains { $0.id == record.id }
                    Button {
                        guard !have else { return }
                        store.claim(record, reason: "Picked by you")
                        Haptics.success()
                        claimed = record
                    } label: {
                        HStack(spacing: 12) {
                            RecordSleeve(record: record, size: 52)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.title).font(.subheadline.bold()).lineLimit(2)
                                Text(record.artist).font(.caption).foregroundStyle(Theme.textDim)
                            }
                            Spacer()
                            if have { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay {
                if loading { ProgressView() }
                else if results.isEmpty && error == nil {
                    ContentUnavailableView("Find an album", systemImage: "opticaldisc",
                                           description: Text("Any album on Apple Music. It goes on the wall."))
                }
            }
            .searchable(text: $term, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Album or artist")
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle(store.state.digs > 0 ? "Pick a record (\(store.state.digs))" : "Pick a record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(item: $claimed, onDismiss: { if store.state.digs == 0 { dismiss() } }) { record in
                RecordReveal(record: record).presentationDetents([.medium])
            }
        }
        .themedRoot()
    }

    private func search() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            results = try await RecordCatalog.searchAlbums(term)
            if results.isEmpty { error = "Nothing found for “\(term)”." }
        } catch {
            self.error = "Couldn't search right now — check your connection."
        }
    }
}

// MARK: - Spotify

private struct SpotifySection: View {
    private var spotify: SpotifyLink { .shared }
    private var store: BuddyStore { .shared }
    @AppStorage(SpotifyLink.clientIDKey) private var clientID = ""
    @State private var showSetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Spotify")
            if spotify.isLinked {
                HStack {
                    Label("Linked", systemImage: "checkmark.circle.fill").foregroundStyle(Color(hex: 0x1DB954))
                    Spacer()
                    Text("\(store.state.spotifyQueue.count) albums queued")
                        .font(.caption).foregroundStyle(Theme.textDim)
                }
                Text("Records you earn come from what you actually listen to — least-played first, building up to your most-played album as the prize for finishing a tour.")
                    .font(.footnote).foregroundStyle(Theme.textDim)
                HStack {
                    Button("Refresh listening") { Task { await spotify.refreshQueue() } }
                    Spacer()
                    Button("Unlink", role: .destructive) { spotify.unlink() }
                }
                .font(.subheadline)
                .disabled(spotify.busy)
            } else {
                Text("Link Spotify and the records you earn become the albums you listen to: least-played first, your most-played saved for finishing the tour.")
                    .font(.footnote).foregroundStyle(Theme.textDim)
                Button {
                    Task { await spotify.link() }
                } label: {
                    Label(spotify.busy ? "Linking…" : "Link Spotify", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Color(hex: 0x1DB954))
                .disabled(spotify.busy)
                DisclosureGroup("Set up (one time)", isExpanded: $showSetup) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Go to developer.spotify.com → Dashboard → Create app.\n2. Add the Redirect URI below and tick “Web API”.\n3. Under User Management, add the email of your Spotify account.\n4. Paste the app's Client ID here.")
                            .font(.caption).foregroundStyle(Theme.textDim)
                        HStack {
                            Text(SpotifyLink.redirectURI).font(.caption.monospaced())
                            Spacer()
                            Button("Copy") { UIPasteboard.general.string = SpotifyLink.redirectURI }
                                .font(.caption)
                        }
                        TextField("Client ID", text: $clientID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.caption.monospaced())
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.top, 6)
                }
                .font(.subheadline)
            }
            if spotify.busy { ProgressView() }
            if let error = spotify.lastError {
                Text(error).font(.caption).foregroundStyle(Theme.danger)
            }
        }
    }
}

// MARK: - Buddy

private struct BuddyEditor: View {
    let plan: Plan
    let targets: DailyTargets
    private var store: BuddyStore { .shared }
    @State private var name = ""
    @State private var failed: String?
    @State private var buddyIcon = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Who runs the studio")
                SpeciesPicker(selection: Binding(get: { store.state.species },
                                                 set: { store.setSpecies($0) }))
                HStack {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { store.rename(name) }
                    Button("Save") { store.rename(name); Haptics.selection() }
                        .buttonStyle(.bordered)
                }
                Text("Changing the look or the name keeps everything — records, gear, notes and the tour.")
                    .font(.caption).foregroundStyle(Theme.textDim)
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("App icon")
                HStack(spacing: 12) {
                    Sprite(store.state.species.asset, size: 44)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: 0x312E81), Color(hex: 0x1E1B4B)],
                                                 startPoint: .top, endPoint: .bottom)))
                    Text(buddyIcon
                         ? "\(store.state.name) is your app icon. It changes with the look."
                         : "Put \(store.state.name) on your home screen.")
                        .font(.footnote).foregroundStyle(Theme.textDim)
                    Spacer()
                }
                if !buddyIcon {
                    Button("Use as app icon") {
                        Haptics.selection()
                        store.useBuddyAsAppIcon()
                        buddyIcon = true
                    }
                        .buttonStyle(.bordered).tint(Theme.accent)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Encores · \(store.state.encores)/\(StudioCatalog.maxEncores)")
                HStack(spacing: 12) {
                    Sprite("admission_tickets", size: 44)
                    Text("Miss a day and an Encore covers it automatically, so the streak keeps going. Hold up to two.")
                        .font(.footnote).foregroundStyle(Theme.textDim)
                }
                Button {
                    if store.buyEncore(rate: store.rate(plan: plan, targets: targets)) {
                        Haptics.success(); failed = nil
                    } else {
                        failed = store.state.encores >= StudioCatalog.maxEncores
                            ? "You're holding the max already." : "Not enough notes yet."
                    }
                } label: {
                    HStack {
                        Text("Buy an Encore")
                        Spacer()
                        Sprite("musical_note", size: 14)
                        Text(IdleEngine.format(store.encorePrice(rate: store.rate(plan: plan, targets: targets)))).monospacedDigit()
                    }
                }
                .buttonStyle(.bordered).tint(Theme.accent)
                if let failed { Text(failed).font(.caption).foregroundStyle(Theme.danger) }
            }
        }
        .onAppear {
            name = store.state.name
            buddyIcon = store.usingBuddyIcon
        }
    }
}

/// The six buddies, as a grid of sprites. Shared with onboarding.
struct SpeciesPicker: View {
    @Binding var selection: Species

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(Species.allCases) { species in
                let selected = species == selection
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.3)) { selection = species }
                } label: {
                    VStack(spacing: 4) {
                        Sprite(species.asset, size: selected ? 60 : 50)
                        Text(species.label).font(.caption.bold())
                            .foregroundStyle(selected ? .primary : Theme.textDim)
                    }
                    .frame(maxWidth: .infinity, minHeight: 92)
                    .background(RoundedRectangle(cornerRadius: 14)
                        .fill(selected ? Theme.accent.opacity(0.18) : Theme.surface2))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(selected ? Theme.accent : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
