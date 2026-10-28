import Foundation
import Observation
import UIKit

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

    // Notes. Day-to-day notes are derived from the log; this is everything
    // else (one-off awards, gifts), banked so it can never be taken back.
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
}

/// Something worth a toast.
struct BuddyAward: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var big = false
}

enum GiftResult {
    case notes(Int)
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
        // A head start — the endowed-progress effect. Enough for one small
        // thing on day one, so the shop is a place you've already been.
        s.bank = 60
        s.awarded = ["starter"]
        s.lastSeenEarned = 60
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
    }

    // MARK: Notes

    func earned(plan: Plan, targets: DailyTargets) -> Int {
        BuddyEngine.notesFromLogs(plan: plan, targets: targets) + state.bank
    }

    func balance(plan: Plan, targets: DailyTargets) -> Int {
        max(0, earned(plan: plan, targets: targets) - state.spent)
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

    // MARK: Sync

    /// Pay out everything the log has earned since last time. Idempotent:
    /// every one-off award has a key, and a key only ever pays once.
    @discardableResult
    func sync(plan: Plan, targets: DailyTargets) -> [BuddyAward] {
        var s = state
        var awards: [BuddyAward] = []

        // Existing users meet the studio for the first time: their tour starts
        // where their plan did, with the same head start a new user gets.
        if s.tourStart == nil {
            s.tourStart = plan.startingWeight
            s.tourStartDate = Calendar.current.startOfDay(for: plan.startDate)
        }
        if !s.awarded.contains("starter") {
            s.awarded.append("starter")
            s.bank += 60
        }
        for id in StudioCatalog.starter where !s.owned.contains(id) {
            s.owned.append(id)
            if let g = StudioCatalog.gear(id), s.placed[g.slot.rawValue] == nil {
                s.placed[g.slot.rawValue] = id
            }
        }
        var awarded = Set(s.awarded)
        func pay(_ key: String, _ body: () -> Void) {
            guard !awarded.contains(key) else { return }
            awarded.insert(key)
            s.awarded.append(key)
            body()
        }

        let tour = BuddyEngine.tour(plan: plan, number: s.tourNumber,
                                    start: s.tourStart ?? plan.startingWeight,
                                    since: s.tourStartDate ?? plan.startDate)

        // Every whole pound off the trend: a record.
        if tour.poundsBanked > 0 {
            for lb in 1...tour.poundsBanked {
                pay("t\(s.tourNumber).lb\(lb)") {
                    s.digs += 1
                    s.bank += 20
                    s.newLowDay = Date()
                    awards.append(BuddyAward(text: "New low — \(lb) lb down. A record is yours.", big: true))
                }
            }
        }

        // Every finished track: notes and the track's exclusive gear. The last
        // track of a tour also gets the most-played album, if Spotify's linked.
        if tour.total > 0, tour.tracksDone > 0 {
            for t in 1...tour.tracksDone {
                pay("t\(s.tourNumber).track\(t)") {
                    s.bank += 100
                    var text = "Finished “\(Tour.trackName(t))”. +100 notes"
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
                        r.addedAt = Date()
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
                s.bank += days >= 30 ? 100 : 40
                awards.append(BuddyAward(text: "\(days)-day streak. +\(days >= 30 ? 100 : 40) notes"))
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

        // Daily notes: report what's new since the last look.
        let earnedNow = BuddyEngine.notesFromLogs(plan: plan, targets: targets) + s.bank
        if let seen = s.lastSeenEarned, earnedNow > seen, awards.isEmpty {
            awards.append(BuddyAward(text: "+\(earnedNow - seen) notes"))
        }
        s.lastSeenEarned = earnedNow

        state = s
        return awards
    }

    // MARK: Shop

    func owns(_ gear: Gear) -> Bool { state.owned.contains(gear.id) }

    func placed(in slot: StudioSlot) -> Gear? {
        state.placed[slot.rawValue].flatMap(StudioCatalog.gear)
    }

    func buy(_ gear: Gear, price: Int, plan: Plan, targets: DailyTargets) -> Bool {
        guard !owns(gear), !gear.exclusive, balance(plan: plan, targets: targets) >= price else { return false }
        state.spent += price
        state.owned.append(gear.id)
        state.placed[gear.slot.rawValue] = gear.id
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

    func buyEncore(plan: Plan, targets: DailyTargets) -> Bool {
        guard state.encores < StudioCatalog.maxEncores,
              balance(plan: plan, targets: targets) >= StudioCatalog.encorePrice else { return false }
        state.spent += StudioCatalog.encorePrice
        state.encores += 1
        return true
    }

    func buyRecord(plan: Plan, targets: DailyTargets) -> Bool {
        guard balance(plan: plan, targets: targets) >= StudioCatalog.recordPrice else { return false }
        state.spent += StudioCatalog.recordPrice
        state.digs += 1
        return true
    }

    // MARK: Gift

    /// A gift a day, once something's been logged — so it's attached to
    /// showing up, not just opening the app. What's inside varies (a variable
    /// reward is what makes it worth checking), but it's seeded by the date so
    /// it can't be rerolled.
    func giftAvailable(plan: Plan, targets: DailyTargets) -> Bool {
        if let last = state.lastGiftDay, Calendar.current.isDateInToday(last) { return false }
        let today = Calendar.current.startOfDay(for: Date())
        guard let day = plan.days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) })
        else { return false }
        return !BuddyEngine.choresDone(day: day, targets: targets).isEmpty
    }

    func openGift() -> GiftResult {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        var rng = SplitMix(seed: UInt64(day) &* 0x9E3779B97F4A7C15)
        state.lastGiftDay = Date()
        if rng.next() % 100 < 12 {
            state.digs += 1
            return .dig
        }
        let notes = [10, 15, 15, 20, 20, 25, 30, 40][Int(rng.next() % 8)]
        state.bank += notes
        state.lastSeenEarned = (state.lastSeenEarned ?? 0) + notes
        return .notes(notes)
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
        s.bank = 400
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
