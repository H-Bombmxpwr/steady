import Foundation
import Observation
import UIKit
import WidgetKit

/// Which animal runs the studio. Fluent Emoji 3D sprites, chosen for being
/// full-bodied and readable at small sizes.
enum Species: String, CaseIterable, Identifiable, Codable {
    case penguin, owl, otter, hedgehog, blackCat, chipmunk

    var id: String { rawValue }

    var asset: String {
        switch self {
        case .blackCat: return "Studio/black_cat"
        default: return "Studio/\(rawValue)"
        }
    }

    /// The alternate app icon of this buddy in the studio.
    var iconName: String {
        switch self {
        case .blackCat: return "Icon-Buddy-BlackCat"
        default: return "Icon-Buddy-\(rawValue.capitalized)"
        }
    }

    var label: String {
        switch self {
        case .penguin: return "Penguin"
        case .owl: return "Owl"
        case .otter: return "Otter"
        case .hedgehog: return "Hedgehog"
        case .blackCat: return "Black Cat"
        case .chipmunk: return "Chipmunk"
        }
    }

    var defaultName: String {
        switch self {
        case .penguin: return "Pip"
        case .owl: return "Hoot"
        case .otter: return "Mo"
        case .hedgehog: return "Bramble"
        case .blackCat: return "Vinyl"
        case .chipmunk: return "Peanut"
        }
    }

    /// One line about who they are, for the picker.
    var bio: String {
        switch self {
        case .penguin: return "Formal attire, informal taste. Will play anything twice."
        case .owl: return "Up late. Has opinions about mastering."
        case .otter: return "Holds hands with the records so they don't drift apart."
        case .hedgehog: return "Small, prickly about vinyl care, very soft otherwise."
        case .blackCat: return "Sleeps on the warm amp. Lucky for you."
        case .chipmunk: return "Hoards records like acorns. Knows every B-side."
        }
    }
}

/// A record in the crate — a real album, from Spotify or Apple's catalog.
struct CollectedRecord: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var artist: String
    var artworkURL: String?
    /// 30-second preview, resolved through Apple's catalog when first played.
    var previewURL: String?
    var spotifyURL: String?
    var addedAt: Date = Date()
    /// Why it's here: "1 lb down", "Bought", "Today's gift"…
    var reason: String = ""
}

struct BuddyState: Codable {
    var species: Species = .penguin
    var name: String = Species.penguin.defaultName

    // Tour
    var tourNumber: Int = 1
    var tourStart: Double?
    var tourStartDate: Date?

    // The balance. Idle income can't be derived from the log the way the
    // first version's notes were, so it's stored; `nil` means this state
    // predates the idle layer and gets migrated on the next sync.
    var notes: Double?
    var lifetimeNotes: Double = 0
    var generators: [String: Int] = [:]
    /// When the royalty jar was last emptied.
    var jarSince: Date?
    /// Sound-check items already paid, as "yyyy-MM-dd|chore". Recent days only.
    var paidChores: [String] = []
    /// The furthest the trend has ever got toward the goal, 0…1. Unlocks are
    /// against this, so a rebound never re-locks anything.
    var peakProgress: Double = 0
    /// Last computed food health, 0…1, for the widget.
    var health: Double = 0.5

    // Pre-idle bookkeeping, kept so old states migrate.
    var bank: Int = 0
    var spent: Int = 0
    var awarded: [String] = []
    var lastSeenEarned: Int?

    // Studio
    var owned: [String] = StudioCatalog.starter
    var placed: [String: String] = Dictionary(uniqueKeysWithValues:
        StudioCatalog.starterPlacement.map { ($0.key.rawValue, $0.value) })
    var records: [CollectedRecord] = []
    /// Records earned but not yet picked.
    var digs: Int = 0
    var encores: Int = 0

    var lastGiftDay: Date?
    var newLowDay: Date?

    /// Spotify albums waiting to be earned, least-listened first.
    var spotifyQueue: [CollectedRecord] = []
    var spotifyRefreshed: Date?

    init() {}

    // Field by field, every one optional: a synthesized decoder fails the
    // whole state when a field it expects is missing, and a failed decode
    // here means a player's studio silently resets. Adding a field must
    // never cost anyone their progress.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BuddyState()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        species = v(.species, d.species)
        name = v(.name, d.name)
        tourNumber = v(.tourNumber, d.tourNumber)
        tourStart = v(.tourStart, d.tourStart)
        tourStartDate = v(.tourStartDate, d.tourStartDate)
        notes = v(.notes, d.notes)
        lifetimeNotes = v(.lifetimeNotes, d.lifetimeNotes)
        generators = v(.generators, d.generators)
        jarSince = v(.jarSince, d.jarSince)
        paidChores = v(.paidChores, d.paidChores)
        peakProgress = v(.peakProgress, d.peakProgress)
        health = v(.health, d.health)
        bank = v(.bank, d.bank)
        spent = v(.spent, d.spent)
        awarded = v(.awarded, d.awarded)
        lastSeenEarned = v(.lastSeenEarned, d.lastSeenEarned)
        owned = v(.owned, d.owned)
        placed = v(.placed, d.placed)
        records = v(.records, d.records)
        digs = v(.digs, d.digs)
        encores = v(.encores, d.encores)
        lastGiftDay = v(.lastGiftDay, d.lastGiftDay)
        newLowDay = v(.newLowDay, d.newLowDay)
        spotifyQueue = v(.spotifyQueue, d.spotifyQueue)
        spotifyRefreshed = v(.spotifyRefreshed, d.spotifyRefreshed)
    }
}

/// Something worth a toast.
struct BuddyAward: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var big = false
}

enum GiftResult {
    case notes(Double)
    case dig
}

@MainActor
@Observable
final class BuddyStore {
    static let shared = BuddyStore()

    private nonisolated static let key = "buddy.state.v1"

    private(set) var state: BuddyState {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(BuddyState.self, from: data) {
            state = decoded
        } else {
            state = BuddyState()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        // The widgets and the Live Activity draw the buddy too, and they can
        // only see the App Group.
        let group = UserDefaults(suiteName: appGroupID)
        group?.set(state.species.rawValue, forKey: WidgetSnapshot.buddySpeciesKey)
        group?.set(state.name, forKey: WidgetSnapshot.buddyNameKey)
    }

    // MARK: App icon

    static let appIconKey = "ui.appIcon"   // shared with Settings → App Icon

    var usingBuddyIcon: Bool {
        (UserDefaults.standard.string(forKey: Self.appIconKey) ?? "").hasPrefix("Icon-Buddy-")
    }

    func useBuddyAsAppIcon() {
        let name = state.species.iconName
        UIApplication.shared.setAlternateIconName(name) { error in
            if error == nil { UserDefaults.standard.set(name, forKey: Self.appIconKey) }
        }
    }

    /// Plain read for places that can't hop onto the main actor (notifications).
    nonisolated static var savedName: String {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(BuddyState.self, from: data) else {
            return Species.penguin.defaultName
        }
        return s.name
    }

    // MARK: Setup

    /// Onboarding: a brand-new buddy, a brand-new tour. Wipes everything, so
    /// a fresh start after "Erase All Data" is genuinely fresh.
    func setUp(species: Species, name: String, startWeight: Double, startDate: Date) {
        var s = BuddyState()
        s.species = species
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        s.name = trimmed.isEmpty ? species.defaultName : trimmed
        s.tourStart = startWeight
        s.tourStartDate = Calendar.current.startOfDay(for: startDate)
        // A head start — the endowed-progress effect. Enough for the first
        // busker and a little something, so the shop is a place you've
        // already been.
        s.notes = 60
        s.lifetimeNotes = 60
        s.jarSince = Date()
        s.awarded = ["starter"]
        state = s
    }

    func rename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.name = String(trimmed.prefix(20))
    }

    /// A new look keeps everything — records, gear, notes, the tour. If the
    /// app icon was the old buddy, it follows along.
    func setSpecies(_ species: Species) {
        state.species = species
        if usingBuddyIcon { useBuddyAsAppIcon() }
    }

    func eraseAll() {
        RecordPlayer.shared.stop()
        state = BuddyState()
        SpotifyLink.shared.unlink()
        UserDefaults(suiteName: appGroupID)?.removeObject(forKey: BuddyWidgetStats.key)
    }

    // MARK: The economy

    var notes: Double { state.notes ?? 0 }
    var progress: Double { state.peakProgress }

    private var bandmates: Int {
        state.owned.compactMap(StudioCatalog.gear).filter { $0.slot == .band }.count
    }

    private var gearCount: Int {
        state.owned.filter { !StudioCatalog.starter.contains($0) }.count - bandmates
    }

    func today(_ plan: Plan) -> DayLog? {
        plan.days.first { Calendar.current.isDateInToday($0.date) }
    }

    func multipliers(plan: Plan, targets: DailyTargets) -> IdleEngine.Multipliers {
        var m = IdleEngine.Multipliers()
        m.progress = IdleEngine.progressMultiplier(state.peakProgress)
        m.health = IdleEngine.healthMultiplier(state.health)
        let done = today(plan).map { BuddyEngine.choresDone(day: $0, targets: targets).count } ?? 0
        m.hype = IdleEngine.hypeMultiplier(choresDone: done)
        m.collection = IdleEngine.collectionMultiplier(gear: gearCount, bandmates: bandmates)
        return m
    }

    /// Notes per second right now.
    func rate(plan: Plan, targets: DailyTargets) -> Double {
        IdleEngine.baseRate(levels: state.generators) * multipliers(plan: plan, targets: targets).total
    }

    var jarCapacity: TimeInterval { IdleEngine.jarHours * 3600 }

    /// What's in the jar at `date`, at `rate`.
    func jar(rate: Double, at date: Date = Date()) -> Double {
        let since = state.jarSince ?? date
        return rate * min(jarCapacity, max(0, date.timeIntervalSince(since)))
    }

    func jarFullAt() -> Date { (state.jarSince ?? Date()).addingTimeInterval(jarCapacity) }

    private func earn(_ amount: Double, into s: inout BuddyState) {
        s.notes = (s.notes ?? 0) + amount
        s.lifetimeNotes += amount
    }

    /// Empty the jar into the balance.
    @discardableResult
    func collect(plan: Plan, targets: DailyTargets) -> Double {
        let amount = jar(rate: rate(plan: plan, targets: targets))
        var s = state
        earn(amount, into: &s)
        s.jarSince = Date()
        state = s
        publishWidget(plan: plan, targets: targets)
        return amount
    }

    // MARK: Promo (generators)

    func level(_ g: Generator) -> Int { state.generators[g.id] ?? 0 }

    func isUnlocked(_ g: Generator) -> Bool { g.unlockAt <= state.peakProgress + 1e-9 }

    var levelCap: Int { Generator.levelCap(progress: state.peakProgress) }

    func buy(_ g: Generator, plan: Plan, targets: DailyTargets) -> Bool {
        let cost = g.cost(level: level(g))
        guard isUnlocked(g), level(g) < levelCap else { return false }
        // Bank what's accrued at the old rate before the rate changes.
        collect(plan: plan, targets: targets)
        guard notes >= cost else { return false }
        var s = state
        s.notes = notes - cost
        s.generators[g.id, default: 0] += 1
        state = s
        publishWidget(plan: plan, targets: targets)
        return true
    }

    // MARK: Tour

    func tour(plan: Plan) -> Tour {
        BuddyEngine.tour(plan: plan, number: state.tourNumber,
                         start: state.tourStart ?? plan.startingWeight,
                         since: state.tourStartDate ?? plan.startDate)
    }

    /// Start counting again from today's trend. Finished tracks and records
    /// from the old tour stay — nothing earned is ever taken back.
    func startNewTour(plan: Plan) {
        let current = CalorieEngine.trendWeight(plan: plan)
        state.tourNumber += 1
        state.tourStart = current
        state.tourStartDate = Calendar.current.startOfDay(for: Date())
    }

    var newLowToday: Bool {
        guard let d = state.newLowDay else { return false }
        return Calendar.current.isDateInToday(d)
    }

    private static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: Sync

    /// Pay out everything the log has earned since last time. Idempotent:
    /// every award has a key, and a key only ever pays once.
    @discardableResult
    func sync(plan: Plan, targets: DailyTargets) -> [BuddyAward] {
        var s = state
        var awards: [BuddyAward] = []
        let now = Date()
        let cal = Calendar.current

        // Existing users meet the studio for the first time: their tour starts
        // where their plan did.
        if s.tourStart == nil {
            s.tourStart = plan.startingWeight
            s.tourStartDate = cal.startOfDay(for: plan.startDate)
        }
        for id in StudioCatalog.starter where !s.owned.contains(id) {
            s.owned.append(id)
            if let g = StudioCatalog.gear(id), s.placed[g.slot.rawValue] == nil {
                s.placed[g.slot.rawValue] = id
            }
        }

        // Progress and health first — everything below is priced off them.
        s.peakProgress = max(s.peakProgress, IdleEngine.goalProgress(plan: plan))
        s.health = IdleEngine.health(plan: plan, today: now)
        state = s
        let rate = self.rate(plan: plan, targets: targets)

        // Migrating a pre-idle state: the old balance carries over, and the
        // sound check it already paid for isn't paid twice.
        if s.notes == nil {
            if !s.awarded.contains("starter") { s.bank += 60; s.awarded.append("starter") }
            let old = BuddyEngine.notesFromLogs(plan: plan, targets: targets) + s.bank - s.spent
            s.notes = Double(max(0, old))
            s.lifetimeNotes = Double(max(0, old))
            s.jarSince = now
            for back in 0...1 {
                guard let d = cal.date(byAdding: .day, value: -back, to: now),
                      let day = plan.days.first(where: { cal.isDate($0.date, inSameDayAs: d) }) else { continue }
                let key = Self.dayKey.string(from: d)
                s.paidChores += BuddyEngine.choresDone(day: day, targets: targets).map { "\(key)|\($0.rawValue)" }
            }
        }
        if s.jarSince == nil { s.jarSince = now }

        var awarded = Set(s.awarded)
        func pay(_ key: String, _ body: () -> Void) {
            guard !awarded.contains(key) else { return }
            awarded.insert(key)
            s.awarded.append(key)
            body()
        }

        // The sound check: each item pays a slice of the studio's output, once.
        var soundCheck = 0.0
        var paid = Set(s.paidChores)
        for back in 0...1 {
            guard let d = cal.date(byAdding: .day, value: -back, to: now),
                  let day = plan.days.first(where: { cal.isDate($0.date, inSameDayAs: d) }) else { continue }
            let key = Self.dayKey.string(from: d)
            for chore in BuddyEngine.choresDone(day: day, targets: targets) {
                let id = "\(key)|\(chore.rawValue)"
                guard !paid.contains(id) else { continue }
                paid.insert(id)
                s.paidChores.append(id)
                soundCheck += IdleEngine.payout(for: chore, rate: rate)
            }
        }
        // Keep the ledger to the last couple of weeks.
        if let cutoff = cal.date(byAdding: .day, value: -14, to: now) {
            let oldest = Self.dayKey.string(from: cutoff)
            s.paidChores.removeAll { $0 < oldest }
        }
        if soundCheck > 0 {
            earn(soundCheck, into: &s)
            awards.append(BuddyAward(text: "+\(IdleEngine.format(soundCheck)) notes from the sound check"))
        }

        let tour = BuddyEngine.tour(plan: plan, number: s.tourNumber,
                                    start: s.tourStart ?? plan.startingWeight,
                                    since: s.tourStartDate ?? plan.startDate)

        // Every whole pound off the trend: a record, and an hour of output.
        if tour.poundsBanked > 0 {
            for lb in 1...tour.poundsBanked {
                pay("t\(s.tourNumber).lb\(lb)") {
                    s.digs += 1
                    earn(max(20, rate * 3600), into: &s)
                    s.newLowDay = now
                    awards.append(BuddyAward(text: "New low — \(lb) lb down. A record is yours.", big: true))
                }
            }
        }

        // Every finished track: six hours of output and the track's gear. The
        // last track also gets the most-played album, if Spotify's linked.
        if tour.total > 0, tour.tracksDone > 0 {
            for t in 1...tour.tracksDone {
                pay("t\(s.tourNumber).track\(t)") {
                    let bonus = max(100, rate * 6 * 3600)
                    earn(bonus, into: &s)
                    var text = "Finished “\(Tour.trackName(t))”. +\(IdleEngine.format(bonus)) notes"
                    if let gear = StudioCatalog.exclusive(forTrack: t, of: tour.trackCount),
                       !s.owned.contains(gear.id) {
                        s.owned.append(gear.id)
                        s.placed[gear.slot.rawValue] = gear.id
                        text += " and the \(gear.name)"
                    } else {
                        s.digs += 1
                        text += " and a bonus record"
                    }
                    if t == tour.trackCount, let headliner = s.spotifyQueue.popLast() {
                        var r = headliner
                        r.reason = "Tour \(s.tourNumber) headliner"
                        r.addedAt = now
                        s.records.append(r)
                        text += " — plus your most-played album"
                    }
                    awards.append(BuddyAward(text: text + ".", big: true))
                }
            }
        }

        // Streak milestones, once each.
        let stats = CalorieEngine.streakStats(plan: plan, targets: targets)
        for days in [3, 7, 14, 30, 50, 75, 100, 150, 200, 365] where stats.current >= days {
            pay("streak\(days)") {
                let bonus = max(days >= 30 ? 100 : 40, rate * 2 * 3600)
                earn(bonus, into: &s)
                awards.append(BuddyAward(text: "\(days)-day streak. +\(IdleEngine.format(bonus)) notes"))
            }
        }

        // Encores cover a missed day automatically, Duolingo-style.
        let covered = BuddyEngine.daysToCover(plan: plan, targets: targets, encores: s.encores)
        if !covered.isEmpty {
            plan.protectedDays.append(contentsOf: covered)
            s.encores -= covered.count
            awards.append(BuddyAward(text: covered.count == 1
                ? "An Encore covered a missed day. Streak's still alive."
                : "Two Encores covered the gap. Streak's still alive."))
        }

        state = s
        publishWidget(plan: plan, targets: targets)
        return awards.sorted { $0.big && !$1.big }
    }

    // MARK: Shop

    func owns(_ gear: Gear) -> Bool { state.owned.contains(gear.id) }

    func isUnlocked(_ gear: Gear) -> Bool {
        StudioCatalog.unlockAt(gear) <= state.peakProgress + 1e-9
    }

    func placed(in slot: StudioSlot) -> Gear? {
        state.placed[slot.rawValue].flatMap(StudioCatalog.gear)
    }

    func buy(_ gear: Gear, price: Double) -> Bool {
        guard !owns(gear), !gear.exclusive, isUnlocked(gear), notes >= price else { return false }
        var s = state
        s.notes = notes - price
        s.owned.append(gear.id)
        s.placed[gear.slot.rawValue] = gear.id
        state = s
        return true
    }

    func place(_ gear: Gear) {
        guard owns(gear) else { return }
        state.placed[gear.slot.rawValue] = gear.id
    }

    func clear(_ slot: StudioSlot) {
        guard slot != .wallpaper, slot != .floor else { return }
        state.placed[slot.rawValue] = nil
    }

    /// Records and Encores never run out, so they're priced in hours of the
    /// studio's output — always worth something, never out of reach.
    func encorePrice(rate: Double) -> Double { max(Double(StudioCatalog.encorePrice), rate * 3600 * 1.5) }
    func recordPrice(rate: Double) -> Double { max(Double(StudioCatalog.recordPrice), rate * 3600 * 3) }

    func buyEncore(rate: Double) -> Bool {
        let price = encorePrice(rate: rate)
        guard state.encores < StudioCatalog.maxEncores, notes >= price else { return false }
        var s = state
        s.notes = notes - price
        s.encores += 1
        state = s
        return true
    }

    func buyRecord(rate: Double) -> Bool {
        let price = recordPrice(rate: rate)
        guard notes >= price else { return false }
        var s = state
        s.notes = notes - price
        s.digs += 1
        state = s
        return true
    }

    // MARK: Gift

    /// A gift a day, once something's been logged — so it's attached to
    /// showing up, not just opening the app. What's inside varies (a variable
    /// reward is what makes it worth checking), but it's seeded by the date so
    /// it can't be rerolled.
    func giftAvailable(plan: Plan, targets: DailyTargets) -> Bool {
        if let last = state.lastGiftDay, Calendar.current.isDateInToday(last) { return false }
        guard let day = today(plan) else { return false }
        return !BuddyEngine.choresDone(day: day, targets: targets).isEmpty
    }

    func openGift(rate: Double) -> GiftResult {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        var rng = SplitMix(seed: UInt64(day) &* 0x9E3779B97F4A7C15)
        var s = state
        s.lastGiftDay = Date()
        if rng.next() % 100 < 12 {
            s.digs += 1
            state = s
            return .dig
        }
        // 10 minutes to an hour of output.
        let minutes = [10.0, 15, 15, 20, 20, 30, 40, 60][Int(rng.next() % 8)]
        let amount = max(minutes, rate * 60 * minutes)
        earn(amount, into: &s)
        state = s
        return .notes(amount)
    }

    // MARK: Records

    /// Spend a dig on an album. From Spotify's queue when one's waiting
    /// (least-listened first), otherwise whatever was picked from search.
    func claim(_ record: CollectedRecord, reason: String) {
        guard state.digs > 0, !state.records.contains(where: { $0.id == record.id }) else { return }
        var r = record
        r.reason = reason
        r.addedAt = Date()
        state.digs -= 1
        state.records.append(r)
        state.spotifyQueue.removeAll { $0.id == r.id }
    }

    /// Reveal the next album from the Spotify queue.
    func revealNextFromSpotify() -> CollectedRecord? {
        guard state.digs > 0, let next = state.spotifyQueue.first else { return nil }
        claim(next, reason: "From your Spotify")
        return state.records.last
    }

    func updatePreview(for id: String, url: String) {
        guard let i = state.records.firstIndex(where: { $0.id == id }) else { return }
        state.records[i].previewURL = url
    }

    func setSpotifyQueue(_ albums: [CollectedRecord]) {
        let have = Set(state.records.map(\.id))
        state.spotifyQueue = albums.filter { !have.contains($0.id) }
        state.spotifyRefreshed = Date()
    }

    // MARK: Widget

    /// What the home-screen widget shows. Written whenever the economy moves;
    /// the widget extrapolates the jar from `rate` and `jarSince` on its own.
    func publishWidget(plan: Plan, targets: DailyTargets) {
        let tour = tour(plan: plan)
        let stats = BuddyWidgetStats(
            name: state.name,
            asset: state.species.asset,
            notes: notes,
            rate: rate(plan: plan, targets: targets),
            jarSince: state.jarSince ?? Date(),
            jarHours: IdleEngine.jarHours,
            health: BuddyHealth(score: state.health).rawValue,
            healthMultiplier: IdleEngine.healthMultiplier(state.health),
            records: state.records.count,
            track: tour.currentTrack,
            trackCount: tour.trackCount,
            toNextTrack: tour.toNextTrack,
            progress: state.peakProgress)
        stats.save()
        WidgetCenter.shared.reloadTimelines(ofKind: "TodayWidget")
    }
}

#if DEBUG
extension BuddyStore {
    /// `-seedStudio`: a furnished room with real records on the walls, for
    /// screenshots and eyeballing the layout without earning it all first.
    func debugSeedStudio(startWeight: Double, startDate: Date) {
        setUp(species: .penguin, name: "Pip", startWeight: startWeight, startDate: startDate)
        let art = "https://is1-ssl.mzstatic.com/image/thumb/"
        let albums: [(Int, String, String, String)] = [
            (594061854, "Rumours", "Fleetwood Mac", "Music124/v4/4d/13/ba/4d13bac3-d3d5-7581-2c74-034219eadf2b/081227970949.jpg"),
            (617154241, "Random Access Memories", "Daft Punk", "Music115/v4/e8/43/5f/e8435ffa-b6b9-b171-40ab-4ff3959ab661/886443919266.jpg"),
            (268443092, "Kind of Blue", "Miles Davis", "Music/7f/9f/d6/mzi.vtnaewef.jpg"),
            (1474815798, "Abbey Road (2019 Mix)", "The Beatles", "Music211/v4/48/53/43/485343e3-dd6a-0034-faec-f4b6403f8108/13UMGIM63890.rgb.jpg"),
            (1440871877, "To Pimp a Butterfly", "Kendrick Lamar", "Music112/v4/b5/a6/91/b5a69171-5232-3d5b-9c15-8963802f83dd/15UMGIM15814.rgb.jpg"),
            (1109714933, "In Rainbows", "Radiohead", "Music126/v4/dd/50/c7/dd50c790-99ac-d3d0-5ab8-e3891fb8fd52/634904032463.png"),
        ]
        var s = state
        s.records = albums.map {
            CollectedRecord(id: "itunes:\($0.0)", title: $0.1, artist: $0.2,
                            artworkURL: art + $0.3 + "/600x600bb.jpg", reason: "Demo")
        }
        let gear = ["speakers", "headphones", "guitar", "lantern", "score", "plant", "couch", "wall.plum", "band.dog", "floor.walnut"]
        s.owned += gear
        for id in gear { if let g = StudioCatalog.gear(id) { s.placed[g.slot.rawValue] = id } }
        s.digs = 1
        s.notes = 25_000
        s.generators = ["busk": 10, "openmic": 6]
        state = s
    }
}
#endif

/// Tiny deterministic PRNG so a day's gift is the same however often the
/// app is opened.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
