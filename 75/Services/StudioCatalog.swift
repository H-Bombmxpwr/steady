import Foundation

// Art: Microsoft Fluent Emoji 3D (MIT) — see THIRD_PARTY_NOTICES.md. Every
// sprite lives under the `Studio/` namespace in Assets.xcassets.

/// Where a piece of gear sits in the studio. One thing per spot; owning more
/// than one lets you swap.
enum StudioSlot: String, CaseIterable, Identifiable, Codable {
    case band, speakers, desk, table, instrument, ceiling, wall, shelf, corner, wallpaper, floor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .band: return "Bandmate"
        case .speakers: return "Speakers"
        case .desk: return "Console"
        case .table: return "Side table"
        case .instrument: return "Instrument"
        case .ceiling: return "Ceiling"
        case .wall: return "Wall"
        case .shelf: return "Shelf"
        case .corner: return "Corner"
        case .wallpaper: return "Walls"
        case .floor: return "Floor"
        }
    }
}

struct Gear: Identifiable, Hashable {
    let id: String
    let name: String
    /// Sprite name under `Studio/`. Wallpapers have none.
    let sprite: String?
    let slot: StudioSlot
    let price: Int
    /// Only unlocks by finishing this track of a tour; never for sale.
    var track: Int? = nil
    /// Wall or floor colors (top, bottom), hex.
    var colors: (UInt32, UInt32)? = nil
    let blurb: String

    static func == (a: Gear, b: Gear) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var asset: String? { sprite.map { "Studio/\($0)" } }
    var exclusive: Bool { track != nil }
}

enum StudioCatalog {
    static let all: [Gear] = [
        // Starter — free, placed on day one so the room is never empty.
        Gear(id: "radio", name: "Old Radio", sprite: "radio", slot: .shelf, price: 0,
             blurb: "Came with the room. Gets one station."),
        Gear(id: "wall.midnight", name: "Midnight", sprite: nil, slot: .wallpaper, price: 0,
             colors: (0x1E1B4B, 0x312E81), blurb: "The default. Good for late sessions."),
        Gear(id: "floor.oak", name: "Oak Boards", sprite: nil, slot: .floor, price: 0,
             colors: (0x5B3A22, 0x2E1D12), blurb: "Creaks on the two and the four."),

        // Bandmates — the long game. Each one moves in and plays along while
        // a record spins. Priced so the band comes together over months.
        Gear(id: "band.snail", name: "Shelly — tour manager", sprite: "snail", slot: .band, price: 450,
             blurb: "Never late. Never early. Exactly on time, eventually."),
        Gear(id: "band.turtle", name: "Tuck — slow jams", sprite: "turtle", slot: .band, price: 550,
             blurb: "Only plays ballads. Has never once rushed a tempo."),
        Gear(id: "band.duck", name: "Quincy — bass", sprite: "duck", slot: .band, price: 650,
             blurb: "Keeps it low and steady. Mostly paddling underneath."),
        Gear(id: "band.rabbit", name: "Juniper — tambourine", sprite: "rabbit", slot: .band, price: 750,
             blurb: "Fastest hands in the business. Slightly too much tambourine."),
        Gear(id: "band.dog", name: "Biscuit — drums", sprite: "dog", slot: .band, price: 850,
             blurb: "Hits everything with total sincerity. Good boy."),
        Gear(id: "band.beaver", name: "Dam — roadie", sprite: "beaver", slot: .band, price: 950,
             blurb: "Built the stage. Built a second stage. Can't stop."),
        Gear(id: "band.parrot", name: "Polly — backing vocals", sprite: "parrot", slot: .band, price: 1100,
             blurb: "Sings every chorus back to you, louder."),
        Gear(id: "band.flamingo", name: "Rosa — keytar", sprite: "flamingo", slot: .band, price: 1250,
             blurb: "Plays standing on one leg. Refuses to explain."),
        Gear(id: "band.dodo", name: "Dodo — lead guitar", sprite: "dodo", slot: .band, price: 1400,
             blurb: "Extinct? No. On a very long hiatus."),
        Gear(id: "band.peacock", name: "Monty — frontman", sprite: "peacock", slot: .band, price: 1600,
             blurb: "The fans come for him. He knows it."),

        // Speakers & desk
        Gear(id: "speakers", name: "Bookshelf Speakers", sprite: "speaker_high_volume", slot: .speakers, price: 150,
             blurb: "A matched pair. The deck finally sounds like something."),
        Gear(id: "headphones", name: "Studio Headphones", sprite: "headphone", slot: .desk, price: 90,
             blurb: "Closed-back. For hearing the bass you've been missing."),

        // Instruments
        Gear(id: "maracas", name: "Maracas", sprite: "maracas", slot: .instrument, price: 60,
             blurb: "Every band needs someone who can't be stopped."),
        Gear(id: "flute", name: "Wooden Flute", sprite: "flute", slot: .instrument, price: 90,
             blurb: "Three notes, played very sincerely."),
        Gear(id: "mic", name: "Stage Mic", sprite: "microphone", slot: .instrument, price: 120,
             blurb: "Karaoke night, every night."),
        Gear(id: "drum", name: "Snare", sprite: "drum", slot: .instrument, price: 140,
             blurb: "The neighbours have been notified."),
        Gear(id: "djembe", name: "Djembe", sprite: "long_drum", slot: .instrument, price: 140,
             blurb: "Hand drum. Good for thinking."),
        Gear(id: "trumpet", name: "Trumpet", sprite: "trumpet", slot: .instrument, price: 160,
             blurb: "Loud on purpose."),
        Gear(id: "banjo", name: "Banjo", sprite: "banjo", slot: .instrument, price: 180,
             blurb: "Front-porch certified."),
        Gear(id: "guitar", name: "Electric Guitar", sprite: "guitar", slot: .instrument, price: 200,
             blurb: "Cherry red. Plugged into nothing, yet."),
        Gear(id: "accordion", name: "Accordion", sprite: "accordion", slot: .instrument, price: 200,
             blurb: "A whole band you wear."),
        Gear(id: "violin", name: "Violin", sprite: "violin", slot: .instrument, price: 220,
             blurb: "For the slow songs."),

        // Ceiling
        Gear(id: "bulb", name: "Bare Bulb", sprite: "light_bulb", slot: .ceiling, price: 40,
             blurb: "Rehearsal-room lighting."),
        Gear(id: "lantern", name: "Paper Lantern", sprite: "red_paper_lantern", slot: .ceiling, price: 90,
             blurb: "Warmer. Everyone looks better."),
        Gear(id: "balloon", name: "Balloon", sprite: "balloon", slot: .ceiling, price: 60,
             blurb: "Left over from a party nobody remembers."),
        Gear(id: "chime", name: "Wind Chime", sprite: "wind_chime", slot: .ceiling, price: 80,
             blurb: "Plays in a key of its own choosing."),
        Gear(id: "planet", name: "Planet Mobile", sprite: "ringed_planet", slot: .ceiling, price: 180,
             blurb: "For the space-rock phase."),

        // Wall
        Gear(id: "picture", name: "Landscape Print", sprite: "framed_picture", slot: .wall, price: 60,
             blurb: "Somewhere you'll go on tour one day."),
        Gear(id: "score", name: "Framed Score", sprite: "musical_score", slot: .wall, price: 80,
             blurb: "Nobody can read it. It looks great."),
        Gear(id: "rainbow", name: "Rainbow Decal", sprite: "rainbow", slot: .wall, price: 110,
             blurb: "Unironically."),
        Gear(id: "poster.sunrise", name: "Sunrise Poster", sprite: "sunrise_over_mountains", slot: .wall, price: 140,
             blurb: "Morning-weigh-in energy."),
        Gear(id: "poster.city", name: "City Poster", sprite: "cityscape_at_dusk", slot: .wall, price: 160,
             blurb: "Tour stop you'll play one day."),
        Gear(id: "poster.night", name: "Night Skyline", sprite: "night_with_stars", slot: .wall, price: 180,
             blurb: "For the 2 a.m. sessions."),
        Gear(id: "poster.fireworks", name: "Fireworks Poster", sprite: "fireworks", slot: .wall, price: 220,
             blurb: "The end-of-set feeling, framed."),
        Gear(id: "poster.galaxy", name: "Galaxy Print", sprite: "milky_way", slot: .wall, price: 260,
             blurb: "Very big. Makes the room feel bigger."),

        // Shelf
        Gear(id: "coffee", name: "Coffee", sprite: "hot_beverage", slot: .table, price: 30,
             blurb: "Something warm between takes."),
        Gear(id: "candle", name: "Candle", sprite: "candle", slot: .table, price: 40,
             blurb: "Vibes, measured in lumens."),
        Gear(id: "plant", name: "Potted Plant", sprite: "potted_plant", slot: .shelf, price: 50,
             blurb: "Needs watering about as often as you do."),
        Gear(id: "books", name: "Liner Notes", sprite: "books", slot: .shelf, price: 60,
             blurb: "Every credit, every session player."),
        Gear(id: "clock", name: "Mantel Clock", sprite: "mantelpiece_clock", slot: .shelf, price: 90,
             blurb: "Keeps time better than the drummer."),
        Gear(id: "bell", name: "Service Bell", sprite: "bell", slot: .table, price: 70,
             blurb: "Ding means encore."),
        Gear(id: "cassette", name: "Mixtape", sprite: "videocassette", slot: .shelf, price: 110,
             blurb: "Side A: songs for the gym. Side B: also songs for the gym."),
        Gear(id: "camera", name: "Tour Camera", sprite: "camera", slot: .shelf, price: 140,
             blurb: "Before-and-after photos, but for the band."),
        Gear(id: "joystick", name: "Arcade Stick", sprite: "joystick", slot: .shelf, price: 160,
             blurb: "Between-takes entertainment."),
        Gear(id: "crystal", name: "Crystal Ball", sprite: "crystal_ball", slot: .shelf, price: 200,
             blurb: "Shows your goal date. Also the trend card does."),

        // Corner
        Gear(id: "sunflower", name: "Sunflower", sprite: "sunflower", slot: .corner, price: 50,
             blurb: "Turns toward whatever's playing."),
        Gear(id: "tulip", name: "Tulip", sprite: "tulip", slot: .corner, price: 50,
             blurb: "Small, pink, committed."),
        Gear(id: "cactus", name: "Cactus", sprite: "cactus", slot: .corner, price: 60,
             blurb: "Unkillable. Inspirational, honestly."),
        Gear(id: "bear", name: "Teddy Bear", sprite: "teddy_bear", slot: .corner, price: 90,
             blurb: "Front-row seat, every show."),
        Gear(id: "couch", name: "Listening Couch", sprite: "couch_and_lamp", slot: .corner, price: 240,
             blurb: "For playing an album front to back like it's meant to be."),
        Gear(id: "bouquet", name: "Bouquet", sprite: "bouquet", slot: .corner, price: 80,
             blurb: "Thrown on stage. Kept forever."),
        Gear(id: "fish", name: "Fish Tank", sprite: "tropical_fish", slot: .corner, price: 180,
             blurb: "The calmest member of the household."),
        Gear(id: "tv", name: "Old TV", sprite: "television", slot: .corner, price: 220,
             blurb: "Only plays concert footage."),
        Gear(id: "palm", name: "Palm Tree", sprite: "palm_tree", slot: .corner, price: 300,
             blurb: "Indoor tropical. Ambitious."),

        // Walls
        Gear(id: "wall.plum", name: "Plum", sprite: nil, slot: .wallpaper, price: 100,
             colors: (0x3B0764, 0x701A75), blurb: "Velvet-curtain energy."),
        Gear(id: "wall.forest", name: "Forest", sprite: nil, slot: .wallpaper, price: 100,
             colors: (0x052E16, 0x14532D), blurb: "Cabin recording session."),
        Gear(id: "wall.sunset", name: "Sunset", sprite: nil, slot: .wallpaper, price: 150,
             colors: (0x7C2D12, 0xBE185D), blurb: "Golden hour, all day."),
        Gear(id: "wall.cream", name: "Cream", sprite: nil, slot: .wallpaper, price: 150,
             colors: (0x78716C, 0xD6D3D1), blurb: "Bright, clean, a little Scandinavian."),
        Gear(id: "wall.ocean", name: "Deep Ocean", sprite: nil, slot: .wallpaper, price: 200,
             colors: (0x082F49, 0x0E7490), blurb: "Underwater reverb."),
        Gear(id: "wall.neon", name: "Neon Club", sprite: nil, slot: .wallpaper, price: 300,
             colors: (0x18181B, 0xC026D3), blurb: "After-hours. The good kind."),
        Gear(id: "wall.gold", name: "Gold Record", sprite: nil, slot: .wallpaper, price: 450,
             colors: (0x451A03, 0xCA8A04), blurb: "For a studio that's earned it."),

        // Floors
        Gear(id: "floor.walnut", name: "Walnut", sprite: nil, slot: .floor, price: 150,
             colors: (0x3F2A1D, 0x1C120C), blurb: "Darker, richer, quieter."),
        Gear(id: "floor.concrete", name: "Garage Concrete", sprite: nil, slot: .floor, price: 200,
             colors: (0x57534E, 0x292524), blurb: "Where every good band starts."),
        Gear(id: "floor.carpet", name: "Red Carpet", sprite: nil, slot: .floor, price: 300,
             colors: (0x991B1B, 0x450A0A), blurb: "Walk on it like you mean it."),
        Gear(id: "floor.stage", name: "Black Stage", sprite: nil, slot: .floor, price: 400,
             colors: (0x27272A, 0x09090B), blurb: "Gaffer tape marks included."),

        // Tour exclusives — one per finished track, in order. Never for sale:
        // the only way to get these is pounds off the trend.
        Gear(id: "studio-mic", name: "Studio Mic", sprite: "studio_microphone", slot: .instrument, price: 0, track: 1,
             blurb: "Finished Track 1. The real one, with the shock mount."),
        Gear(id: "fader", name: "Fader", sprite: "level_slider", slot: .desk, price: 0, track: 2,
             blurb: "Finished Track 2. Bring it up slowly."),
        Gear(id: "disco", name: "Mirror Ball", sprite: "mirror_ball", slot: .ceiling, price: 0, track: 3,
             blurb: "Finished Track 3. The room changed when this went up."),
        Gear(id: "sax", name: "Saxophone", sprite: "saxophone", slot: .instrument, price: 0, track: 4,
             blurb: "Finished Track 4. Solo time."),
        Gear(id: "mixer", name: "Mixing Desk", sprite: "control_knobs", slot: .desk, price: 0, track: 5,
             blurb: "Finished Track 5. You're producing now."),
        Gear(id: "keys", name: "Keyboard", sprite: "musical_keyboard", slot: .instrument, price: 0, track: 6,
             blurb: "Finished Track 6. Eighty-eight keys, all earned."),
        Gear(id: "star", name: "Wall Star", sprite: "glowing_star", slot: .wall, price: 0, track: 7,
             blurb: "Finished Track 7. Headliner energy."),
        Gear(id: "medal", name: "Gold Medal", sprite: "1st_place_medal", slot: .wall, price: 0, track: 8,
             blurb: "Finished Track 8. Hang it where you'll see it."),
    ]

    /// The trophy for finishing a whole tour — always the last track, however
    /// many tracks the tour has.
    static let trophy = Gear(id: "trophy", name: "Tour Trophy", sprite: "trophy", slot: .shelf, price: 0,
                             blurb: "You reached your goal weight. This one doesn't need a caption.")

    static let starter = ["radio", "wall.midnight", "floor.oak"]
    static let starterPlacement: [StudioSlot: String] = [.shelf: "radio", .wallpaper: "wall.midnight",
                                                         .floor: "floor.oak"]

    static let encorePrice = 120
    static let maxEncores = 2

    static func gear(_ id: String) -> Gear? {
        id == trophy.id ? trophy : all.first { $0.id == id }
    }

    /// Move previously placed objects to their new surface without changing
    /// ownership or overwriting a deliberate placement in the destination.
    static func migratePlacement(_ placed: [String: String], owned: [String]) -> [String: String] {
        var result = placed
        for (oldSlot, id) in placed.sorted(by: { $0.key < $1.key }) {
            guard let item = gear(id), item.slot.rawValue != oldSlot else { continue }
            result.removeValue(forKey: oldSlot)
            if result[item.slot.rawValue] == nil { result[item.slot.rawValue] = id }
            if oldSlot == StudioSlot.shelf.rawValue, owned.contains("radio"), result[oldSlot] == nil {
                result[oldSlot] = "radio"
            }
        }
        return result
    }

    static var forSale: [Gear] { all.filter { !$0.exclusive && $0.price > 0 } }

    /// The exclusive for finishing `track` of a tour with `trackCount` tracks.
    /// The last track always pays the trophy; tracks past the exclusives list
    /// pay notes and a record instead.
    static func exclusive(forTrack track: Int, of trackCount: Int) -> Gear? {
        if track == trackCount { return trophy }
        return all.first { $0.track == track }
    }

    // MARK: Tiers — normalized to the goal

    /// Deliberate, stable unlocks: adding an item cannot move existing gear.
    /// A new tier opens every seven qualifying logging days, or sooner when
    /// weight progress reaches it. The trophy remains weight-only.
    static let tierCount = 10
    static let tierItems: [[String]] = [
        ["coffee", "bulb", "candle", "plant", "maracas", "picture", "wall.plum"],
        ["band.snail", "sunflower", "flute", "books", "lantern", "floor.walnut"],
        ["band.turtle", "headphones", "guitar", "tulip", "score", "wall.forest"],
        ["band.duck", "mic", "balloon", "clock", "bear", "wall.sunset", "speakers"],
        ["band.rabbit", "drum", "chime", "bell", "cactus", "wall.cream"],
        ["band.dog", "djembe", "rainbow", "cassette", "bouquet", "floor.concrete"],
        ["band.beaver", "trumpet", "poster.sunrise", "camera", "fish", "wall.ocean"],
        ["band.parrot", "banjo", "poster.city", "joystick", "couch", "floor.carpet", "planet"],
        ["band.flamingo", "accordion", "poster.night", "crystal", "tv", "wall.neon"],
        ["band.dodo", "band.peacock", "violin", "poster.fireworks", "poster.galaxy", "palm", "wall.gold", "floor.stage"],
    ]

    static func tier(_ gear: Gear) -> Int {
        tierItems.firstIndex { $0.contains(gear.id) } ?? 0
    }

    static func unlockAt(_ gear: Gear) -> Double {
        gear.exclusive ? 1 : Double(tier(gear)) / Double(tierCount - 1)
    }

    /// Prices represent 2–4 hours of a reference studio at the tier's unlock.
    /// They are fixed per item: buying generators never raises a gear price.
    /// Coffee is an immediate first purchase alongside the first busker.
    static func price(_ gear: Gear) -> Double {
        guard gear.price > 0 else { return 0 }
        if gear.id == "coffee" { return 30 }
        let p = unlockAt(gear)
        let cap = Generator.levelCap(progress: p)
        let base = IdleEngine.generators.filter { $0.unlockAt <= p + 1e-9 }
            .reduce(0.0) { $0 + Double(cap) * $1.baseRate }
        let referenceRate = base * IdleEngine.progressMultiplier(p) * 1.5
        let hours = gear.slot == .band ? 4.0 : 2.0 + Double(gear.price % 100) / 100
        return (referenceRate * 3600 * hours).rounded()
    }

    /// One item a day at 40% off. Seeded by the date so it's the same deal all
    /// day, and something new to look at tomorrow.
    static func dailyDeal(owned: Set<String>, progress: Double,
                          on date: Date = Date()) -> (gear: Gear, price: Double)? {
        let pool = forSale.filter { !owned.contains($0.id) && unlockAt($0) <= progress + 1e-9 }
        guard !pool.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        let gear = pool[(day &* 7919) % pool.count]
        return (gear, price(gear) * 0.6)
    }
}
