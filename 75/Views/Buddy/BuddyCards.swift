import SwiftUI

/// The top of the weight-loss dashboard: the studio, what the buddy has to
/// say, today's sound check, and anything waiting to be opened.
struct BuddyCard: View {
    let plan: Plan
    let targets: DailyTargets
    let today: Date
    /// Opens today's log — every unfinished chore lives there.
    var openToday: () -> Void
    var openShop: (StudioShopView.Tab) -> Void

    private var store: BuddyStore { .shared }
    @State private var giftResult: String?
    @State private var tapSeed = 0

    private var day: DayLog? {
        plan.days.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }
    private var done: Set<Chore> {
        day.map { BuddyEngine.choresDone(day: $0, targets: targets) } ?? []
    }
    private var tour: Tour { store.tour(plan: plan) }
    private var rate: Double { store.rate(plan: plan, targets: targets) }
    private var health: BuddyHealth { BuddyHealth(score: store.state.health) }

    private var mood: BuddyMood {
        BuddyEngine.mood(done: done,
                         hour: Calendar.current.component(.hour, from: Date()),
                         newLowToday: store.newLowToday,
                         daysAway: BuddyEngine.daysAway(plan: plan),
                         loggedToday: day?.hasActivity ?? false)
    }

    private var line: String {
        let trend = CalorieEngine.weightTrend(plan: plan)
        var weekDelta: Double?
        if let last = trend.last,
           let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: today),
           let then = trend.last(where: { $0.date <= weekAgo }) {
            weekDelta = last.trend - then.trend
        }
        let player = RecordPlayer.shared
        let playing = store.state.records.first { $0.id == player.playingID }
        let ctx = BuddyEngine.LineContext(name: store.state.name, mood: mood, done: done,
                                          tour: tour, records: store.state.records.count,
                                          daysAway: BuddyEngine.daysAway(plan: plan),
                                          nowPlaying: playing.map { "“\(player.track?.name ?? $0.title)”" },
                                          weekDelta: weekDelta,
                                          health: health)
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: today) ?? 0
        return BuddyEngine.line(ctx, seed: dayOfYear + tapSeed)
    }

    var body: some View {
        Card {
            HStack(spacing: 8) {
                // Tap the name to open the studio — the gear, first.
                Button { openShop(.gear) } label: {
                    HStack(spacing: 4) {
                        Text("\(store.state.name)'s Studio")
                            .font(.system(.headline, design: .rounded))
                        Image(systemName: "pencil")
                            .font(.caption.bold())
                            .foregroundStyle(Theme.textDim)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Button { openShop(.records) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "opticaldisc.fill").font(.caption)
                        Text("\(store.state.records.count)").font(.subheadline.bold()).monospacedDigit()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.surface2))
                }
                .buttonStyle(.plain)
                Button { openShop(.promo) } label: {
                    NotesBadge(notes: store.notes)
                }
                .buttonStyle(.plain)
            }

            StudioScene(store: store, mood: mood, health: health,
                        onDeckTap: deckTapped,
                        onRoomTap: { openShop(.gear) })
                .simultaneousGesture(TapGesture().onEnded { tapSeed += 1 })

            NowPlayingBar()
                .animation(.spring(duration: 0.3), value: RecordPlayer.shared.record?.id)

            // What the buddy says. Written by hand, filled with your numbers.
            HStack(alignment: .top, spacing: 8) {
                Sprite(store.state.species.asset, size: 22)
                Text(line)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.easeOut(duration: 0.2), value: line)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))

            economy

            waiting

            soundCheck
        }
    }

    // MARK: The idle economy

    /// The jar, the rate, and the buddy's health — the three numbers the
    /// idle game runs on, with a live counter so the jar visibly fills.
    private var economy: some View {
        let rate = rate
        let m = store.multipliers(plan: plan, targets: targets)
        return VStack(spacing: 8) {
            if rate <= 0 {
                // Nothing earning yet: the first busker is the whole tutorial.
                Button { openShop(.promo) } label: {
                    banner(sprite: "guitar", title: "Start earning",
                           detail: "Buy your first busker in Promo — then the jar fills on its own.",
                           tint: Theme.warn)
                }
                .buttonStyle(.pressable)
            } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let jar = store.jar(rate: rate, at: context.date)
                let full = context.date >= store.jarFullAt()
                Button {
                    let got = store.collect(plan: plan, targets: targets)
                    if got > 0 { Haptics.success() }
                } label: {
                    HStack(spacing: 10) {
                        Sprite("honey_pot", size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("+\(IdleEngine.format(jar)) in the jar")
                                .font(.subheadline.bold()).monospacedDigit()
                                .foregroundStyle(.primary)
                            Text(full ? "Full — collect it, it's not filling any more"
                                      : "\(IdleEngine.format(rate))/s · full \(store.jarFullAt().formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(full ? Theme.warn : Theme.textDim)
                        }
                        Spacer()
                        Text("Collect").font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(Theme.accent.opacity(jar >= 1 ? 0.25 : 0.08)))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.warn.opacity(full ? 0.18 : 0.08)))
                }
                .buttonStyle(.pressable)
                .disabled(jar < 1)
            }
            }

            Button { openShop(.promo) } label: {
                HStack(spacing: 10) {
                    Sprite(health.sprite, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(store.state.name) is \(health.label.lowercased()) · ×\(String(format: "%.2f", m.health))")
                            .font(.subheadline.bold())
                            .foregroundStyle(health.isUnwell ? Theme.danger : .primary)
                        Text(healthLine)
                            .font(.caption).foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.textDim)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
            }
            .buttonStyle(.plain)
        }
    }

    private var healthLine: String {
        switch health {
        case .thriving: return "Eating like this, the studio earns 50% more. Whole foods, mostly green."
        case .healthy: return "Good week of food. The studio's earning a bit extra."
        case .okay: return "Middle of the road. More greens and fewer reds tips it up."
        case .queasy: return "Heavy on the reds lately — the studio's earning less. A green meal helps fast."
        case .sick: return "Feeling rough. Earnings are halved until the food picks up — one good day turns it."
        }
    }

    // MARK: Things waiting to be opened

    @ViewBuilder
    private var waiting: some View {
        if store.state.digs > 0 {
            Button { openShop(.records) } label: {
                banner(sprite: "optical_disk",
                       title: store.state.digs == 1 ? "A record is waiting" : "\(store.state.digs) records are waiting",
                       detail: SpotifyLink.shared.isLinked && !store.state.spotifyQueue.isEmpty
                           ? "Reveal what you earned from your Spotify."
                           : "Pick any album for the crate.",
                       tint: Theme.weightTint)
            }
            .buttonStyle(.pressable)
        }
        if let giftResult {
            banner(sprite: "wrapped_gift", title: giftResult, detail: "Come back tomorrow for another.",
                   tint: Theme.warn)
                .transition(.opacity)
        } else if store.giftAvailable(plan: plan, targets: targets) {
            Button(action: openGift) {
                banner(sprite: "wrapped_gift", title: "Today's gift",
                       detail: "You showed up. Tap to open.", tint: Theme.warn)
            }
            .buttonStyle(.pressable)
        }
    }

    private func banner(sprite: String, title: String, detail: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Sprite(sprite, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.bold()).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(Theme.textDim)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.textDim)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.14)))
    }

    private func openGift() {
        Haptics.success()
        let text: String
        switch store.openGift(rate: rate) {
        case .notes(let n): text = "+\(IdleEngine.format(n)) notes"
        case .dig: text = "A whole record!"
        }
        withAnimation(.spring) { giftResult = text }
    }

    // MARK: Sound check

    private var soundCheck: some View {
        let rate = rate
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SOUND CHECK")
                    .font(.caption.bold()).kerning(1.2)
                    .foregroundStyle(Theme.textDim)
                Spacer()
                Text("\(done.count)/\(Chore.allCases.count) · hype ×\(String(format: "%.2f", IdleEngine.hypeMultiplier(choresDone: done.count)))")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(Theme.textDim)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                      spacing: 8) {
                ForEach(Chore.allCases) { chore in
                    let isDone = done.contains(chore)
                    Button(action: openToday) {
                        HStack(spacing: 6) {
                            Image(systemName: isDone ? "checkmark.circle.fill" : chore.icon)
                                .foregroundStyle(isDone ? Theme.accent : Theme.textDim)
                                .frame(width: 18)
                            Text(chore.label)
                                .font(.caption)
                                .foregroundStyle(isDone ? .primary : Theme.textDim)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text("+\(IdleEngine.format(IdleEngine.payout(for: chore, rate: rate)))")
                                .font(.caption2.bold()).monospacedDigit()
                                .foregroundStyle(isDone ? Theme.accent : Theme.textDim)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 9)
                            .fill(isDone ? Theme.accent.opacity(0.12) : Theme.surface2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func deckTapped() {
        let records = store.state.records
        guard !records.isEmpty else { openShop(.records); return }
        if RecordPlayer.shared.isPlaying {
            RecordPlayer.shared.stop()
        } else if let pick = records.randomElement() {
            RecordPlayer.shared.toggle(pick)
        }
    }
}

// MARK: - The tour

/// The weight journey, in tracks of 5 lb. Shows how close the next finish
/// line is, what it unlocks, and where the next record comes from.
struct TourCard: View {
    let plan: Plan
    @State private var confirmNewTour = false

    private var store: BuddyStore { .shared }
    private var tour: Tour { store.tour(plan: plan) }

    var body: some View {
        let tour = tour
        Card(title: "Tour \(tour.number)", icon: "music.note.list", tint: Theme.weightTint) {
            HStack(alignment: .firstTextBaseline) {
                if let t = tour.currentTrack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Track \(t) of \(tour.trackCount)")
                            .font(.caption).foregroundStyle(Theme.textDim)
                        Text("“\(Tour.trackName(t))”")
                            .font(.system(.title3, design: .rounded).bold())
                    }
                } else {
                    Text("Tour complete").font(.system(.title3, design: .rounded).bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(lb(tour.lostBest) + " lb")
                        .font(.system(.title3, design: .rounded).bold())
                        .foregroundStyle(Theme.accent)
                    Text("best on the trend").font(.caption2).foregroundStyle(Theme.textDim)
                }
            }

            trackBar(tour)

            if let toNext = tour.toNextTrack, let t = tour.currentTrack {
                let unlock = StudioCatalog.exclusive(forTrack: t, of: tour.trackCount)
                HStack(spacing: 8) {
                    if let asset = unlock?.asset { Sprite(asset, size: 28) }
                    Text("\(lb(toNext)) lb on the trend to finish this track" +
                         (unlock.map { " — unlocks the \($0.name)." } ?? " — and a bonus record."))
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Sprite("optical_disk", size: 22)
                Text("Next record when the trend reaches \(lb(tour.nextRecordAt)) lb.")
                    .font(.footnote).foregroundStyle(Theme.textDim)
            }

            if tour.freshStartSuggested || tour.finished {
                Button { confirmNewTour = true } label: {
                    Label(tour.finished ? "Start the next tour" : "Start a new tour from \(lb(tour.current)) lb",
                          systemImage: "arrow.counterclockwise")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
                Text(tour.finished
                     ? "You reached the goal. A new tour keeps the records coming — set a new goal in Settings first if you want one."
                     : "The trend's above where this tour began, so every track is behind a hill. A new tour starts the count from today. Everything you've earned stays.")
                    .font(.caption).foregroundStyle(Theme.textDim)
            }
        }
        .confirmationDialog("Start Tour \(tour.number + 1) from today's trend?",
                            isPresented: $confirmNewTour, titleVisibility: .visible) {
            Button("Start new tour") {
                Haptics.success()
                store.startNewTour(plan: plan)
            }
        } message: {
            Text("Tracks count down from \(lb(tour.current)) lb. Your records, gear and notes all stay.")
        }
    }

    private func lb(_ x: Double) -> String { x.formatted(.number.precision(.fractionLength(1))) }

    private func trackBar(_ tour: Tour) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let total = max(tour.total, 0.1)
            ZStack(alignment: .leading) {
                HStack(spacing: 3) {
                    ForEach(1...tour.trackCount, id: \.self) { t in
                        let lo = tour.trackEnd(t - 1), hi = tour.trackEnd(t)
                        let fill = min(1, max(0, (tour.lostNow - lo) / max(0.1, hi - lo)))
                        let finished = t <= tour.tracksDone
                        GeometryReader { seg in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.surface2)
                                Capsule().fill(finished ? AnyShapeStyle(Theme.gradient)
                                                        : AnyShapeStyle(Theme.accent.opacity(0.7)))
                                    .frame(width: seg.size.width * fill)
                            }
                        }
                        .frame(width: max(4, (w - CGFloat(tour.trackCount - 1) * 3) * (hi - lo) / total))
                    }
                }
                .frame(height: 10)
                .frame(maxHeight: .infinity)

                Sprite(store.state.species.asset, size: 26)
                    .offset(x: max(0, min(w - 26, w * tour.progress - 13)), y: -14)
                    .animation(.spring, value: tour.progress)
            }
            .overlay(alignment: .trailing) {
                Sprite("trophy", size: 22).offset(x: 4, y: -14)
            }
        }
        .frame(height: 40)
    }
}
