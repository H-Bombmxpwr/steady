import SwiftUI

// MARK: - Sprites

/// One Fluent Emoji 3D sprite from the `Studio/` asset namespace.
struct Sprite: View {
    let name: String
    var size: CGFloat

    init(_ name: String, size: CGFloat) {
        self.name = name.hasPrefix("Studio/") ? name : "Studio/\(name)"
        self.size = size
    }

    var body: some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// An album sleeve: the real cover art, or a plain sleeve while it loads.
struct RecordSleeve: View {
    let record: CollectedRecord?
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.06)
                .fill(Color(hex: 0x1F1B2E))
            if let art = record?.artworkURL, let url = URL(string: art) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Sprite("musical_note", size: size * 0.45).opacity(0.5)
                    }
                }
            } else {
                Sprite("musical_note", size: size * 0.45).opacity(0.5)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.06))
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }
}

/// A vinyl disc with the album's art as its centre label. Spins at 33⅓
/// while it's playing.
struct VinylDisc: View {
    let record: CollectedRecord?
    var size: CGFloat
    var spinning: Bool

    var body: some View {
        TimelineView(.animation(paused: !spinning)) { context in
            let angle = spinning
                ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8 * 360
                : 0
            ZStack {
                Circle().fill(Color(hex: 0x0B0B0F))
                ForEach(1..<5) { i in
                    Circle()
                        .stroke(Color.white.opacity(0.07), lineWidth: 0.7)
                        .padding(size * (0.05 + Double(i) * 0.06))
                }
                if let record {
                    RecordSleeve(record: record, size: size * 0.42)
                        .clipShape(Circle())
                } else {
                    Circle().fill(Color(hex: 0x7C2D12)).frame(width: size * 0.36)
                }
                Circle().fill(Color.black).frame(width: size * 0.04)
                // A sheen so the spin reads.
                Circle()
                    .trim(from: 0.05, to: 0.18)
                    .stroke(Color.white.opacity(0.18), lineWidth: size * 0.12)
                    .padding(size * 0.2)
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
        }
    }
}

// MARK: - The buddy

struct BuddySprite: View {
    let species: Species
    var size: CGFloat
    var mood: BuddyMood
    var dancing: Bool
    /// Positive nutrition indicator, shared with the studio header.
    var health: BuddyHealth = .okay

    @State private var hop: CGFloat = 0
    @State private var hearts = 0

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let speed = dancing ? 7.0 : (mood == .sleeping ? 1.2 : 2.2)
            let bob = mood == .sleeping ? 0 : sin(t * speed) * (dancing ? 4 : 2)
            let breathe = 1 + sin(t * (mood == .sleeping ? 1.2 : 2.2)) * 0.02
            let sway = dancing ? sin(t * speed / 2) * 7 : (mood == .newLow ? sin(t * 5) * 5 : 0)

            ZStack(alignment: .bottom) {
                Ellipse()
                    .fill(Color.black.opacity(0.28))
                    .frame(width: size * 0.7, height: size * 0.12)
                    .offset(y: size * 0.03)
                Sprite(species.asset, size: size)
                    .scaleEffect(x: 1, y: breathe, anchor: .bottom)
                    .rotationEffect(.degrees(sway), anchor: .bottom)
                    .offset(y: bob + hop)
                    .opacity(mood == .sleeping ? 0.85 : 1)
            }
            .overlay(alignment: .topTrailing) { moodBadge(t: t) }
            .overlay(alignment: .top) {
                if hearts > 0 {
                    Sprite("red_heart", size: size * 0.3)
                        .offset(y: -size * 0.25)
                        .transition(.asymmetric(insertion: .scale.combined(with: .opacity),
                                                removal: .move(edge: .top).combined(with: .opacity)))
                        .id(hearts)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { pet() }
        .accessibilityLabel("\(species.label)")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func moodBadge(t: Double) -> some View {
        let float = sin(t * 2) * 3
        moodOnlyBadge(t: t, float: float)
    }

    @ViewBuilder
    private func moodOnlyBadge(t: Double, float: Double) -> some View {
        switch mood {
        case .sleeping:
            Sprite("zzz", size: size * 0.32).offset(x: size * 0.1, y: -size * 0.1 + float)
        case .proud:
            Sprite("sparkles", size: size * 0.3).offset(x: size * 0.12, y: -size * 0.05 + float)
        case .newLow:
            Sprite("party_popper", size: size * 0.34).offset(x: size * 0.15, y: -size * 0.08 + float)
        default:
            if dancing {
                Sprite("musical_note", size: size * 0.24)
                    .offset(x: size * 0.12, y: -size * 0.12 + float * 2)
                    .rotationEffect(.degrees(sin(t * 3) * 15))
            }
        }
    }

    private func pet() {
        Haptics.soft()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { hop = -size * 0.18 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { hop = 0 }
        }
        withAnimation(.easeOut(duration: 0.3)) { hearts += 1 }
        let mark = hearts
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            if hearts == mark { withAnimation(.easeIn(duration: 0.3)) { hearts = 0 } }
        }
    }
}

// MARK: - The studio

/// The room. Every placed piece of gear shows up in it; the four newest
/// records hang on the wall and everything older lives in the crate on the
/// floor, which opens to show the whole collection.
struct StudioScene: View {
    let store: BuddyStore
    var mood: BuddyMood
    var health: BuddyHealth = .okay
    var height: CGFloat = 250
    var onDeckTap: () -> Void = {}
    var onRoomTap: () -> Void = {}

    private var player: RecordPlayer { .shared }
    @State private var browsingCrate = false

    private static let wallSpots: [CGFloat] = [106, 148, 190, 232]

    var body: some View {
        GeometryReader { geo in
            // One artboard keeps the furniture and its objects aligned at both
            // dashboard and compact-shop sizes; narrow phones never crop items.
            let scale = min(geo.size.width / 360, geo.size.height / 250)
            // When the card is wider than the artboard, wall and floor carry
            // on out to the edges at the same floor line.
            let floorLine = (geo.size.height - 250 * scale) / 2 + 164 * scale
            let wall = store.placed(in: .wallpaper)?.colors ?? (0x1E1B4B, 0x312E81)
            let floor = store.placed(in: .floor)?.colors ?? (0x5B3A22, 0x2E1D12)
            room
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
                .background {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [Color(hex: wall.0), Color(hex: wall.1)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: floorLine)
                        LinearGradient(colors: [Color(hex: floor.0), Color(hex: floor.1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onRoomTap)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .sheet(isPresented: $browsingCrate) {
            CrateBrowser(records: store.state.records)
                .presentationDetents([.medium, .large])
                .themedRoot()
        }
    }

    private var room: some View {
        let wall = store.placed(in: .wallpaper)?.colors ?? (0x1E1B4B, 0x312E81)
        let floor = store.placed(in: .floor)?.colors ?? (0x5B3A22, 0x2E1D12)
        let records = store.state.records
        let playing = records.first { $0.id == player.playingID }
        let onDeck = playing ?? records.last
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(hex: wall.0), Color(hex: wall.1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: 360, height: 164)
            LinearGradient(colors: [Color(hex: floor.0), Color(hex: floor.1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: 360, height: 86).offset(y: 164)
            Rectangle().fill(Color.black.opacity(0.35))
                .frame(width: 360, height: 3).offset(y: 162)
            Path { path in
                for x in stride(from: -90, through: 450, by: 90) {
                    path.move(to: CGPoint(x: CGFloat(x) * 0.65 + 63, y: 165))
                    path.addLine(to: CGPoint(x: x, y: 250))
                }
            }.stroke(Color.black.opacity(0.12), lineWidth: 1)
            Ellipse().fill(Color(hex: 0x171E35).opacity(0.45))
                .frame(width: 174, height: 30).position(x: 142, y: 225)

            ZStack(alignment: .topTrailing) {
                Sprite("window", size: 46)
                Sprite(isNight ? "crescent_moon" : "sun", size: 16).offset(x: -6, y: 6)
            }.position(x: 45, y: 42)
            item(.wall, size: 40).position(x: 214, y: 39)
            if let ceiling = store.placed(in: .ceiling), let asset = ceiling.asset {
                Rectangle().fill(Color.white.opacity(0.25))
                    .frame(width: 1, height: 14).position(x: 126, y: 7)
                Sprite(asset, size: 30).position(x: 126, y: 28)
            }

            // Objects rest on the ledge rather than being centred over it.
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x926137))
                .frame(width: 92, height: 5).position(x: 294, y: 80)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 3)
            item(.shelf, size: 32).position(x: 294, y: 62)

            ForEach(Array(records.suffix(Self.wallSpots.count).reversed().enumerated()), id: \.element.id) { i, record in
                RecordSleeve(record: record, size: 29)
                    .padding(2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xE7D7B8)))
                    .position(x: Self.wallSpots[i], y: 106)
                    .onTapGesture { RecordPlayer.shared.toggle(record) }
            }

            cornerItem.position(x: 321, y: 149)

            // A console supports the deck and mixing gear. The two speakers
            // have their own ends, so neither can overlap the buddy or desk item.
            furniture(width: 178, height: 38).position(x: 142, y: 200)
            let speakers = store.placed(in: .speakers)?.asset
            Speaker(asset: speakers, playing: playing != nil, mirrored: true)
                .position(x: 68, y: 170)
            Speaker(asset: speakers, playing: playing != nil, mirrored: false)
                .position(x: 216, y: 170)
            deck(record: onDeck, spinning: playing != nil)
                .position(x: 124, y: 167)
                .onTapGesture(perform: onDeckTap)
            item(.desk, size: 28).position(x: 185, y: 171)

            // A separate, always-visible table gives coffee a useful home
            // without replacing the radio or the mixing equipment.
            furniture(width: 54, height: 28).position(x: 322, y: 226)
            item(.table, size: 25).position(x: 322, y: 199)

            if store.placed(in: .instrument) != nil {
                Path { path in
                    path.move(to: CGPoint(x: 17, y: 191))
                    path.addLine(to: CGPoint(x: 28, y: 179))
                    path.addLine(to: CGPoint(x: 39, y: 191))
                }.stroke(Color(hex: 0x27272A), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                item(.instrument, size: 40).position(x: 28, y: 165)
            }
            if !records.isEmpty {
                crate(extra: max(0, records.count - Self.wallSpots.count))
                    .position(x: 31, y: 225)
                    .onTapGesture { Haptics.tap(); browsingCrate = true }
            }
            if let mate = store.placed(in: .band)?.asset {
                Bandmate(asset: mate, size: 42, playing: player.isPlaying)
                    .position(x: 187, y: 223)
            }
            BuddySprite(species: store.state.species, size: 66, mood: mood,
                        dancing: player.isPlaying, health: health)
                .position(x: 260, y: 207)
        }
        .frame(width: 360, height: 250)
    }

    /// A tabletop, front edge and legs share an origin with their objects.
    private func furniture(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            HStack {
                RoundedRectangle(cornerRadius: 2).frame(width: 5)
                Spacer()
                RoundedRectangle(cornerRadius: 2).frame(width: 5)
            }
            .foregroundStyle(Color(hex: 0x42291F))
            .padding(.horizontal, 7).padding(.top, 5)
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [Color(hex: 0xBC8753), Color(hex: 0x79502E)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: 8)
                .overlay(alignment: .top) {
                    Capsule().fill(Color.white.opacity(0.18)).frame(height: 1).padding(.horizontal, 3)
                }
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.18), radius: 2, y: 3)
    }

    @ViewBuilder
    private var cornerItem: some View {
        if let gear = store.placed(in: .corner), let asset = gear.asset {
            if gear.id == "fish" {
                // The source art is a fish, not a tank: give it water and glass.
                ZStack {
                    RoundedRectangle(cornerRadius: 5).fill(Color.cyan.opacity(0.18))
                    RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.55), lineWidth: 2)
                    Sprite(asset, size: 31)
                    VStack { Spacer(); RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xB29B70)).frame(height: 5) }
                }.frame(width: 53, height: 38).offset(y: 7)
            } else if ["sunflower", "tulip", "bouquet", "cactus"].contains(gear.id) {
                ZStack(alignment: .bottom) {
                    Sprite(asset, size: 43).offset(y: -10)
                    UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5)
                        .fill(Color(hex: 0xB66E49)).frame(width: 20, height: 16)
                        .overlay(alignment: .top) {
                            Capsule().fill(Color(hex: 0xDA9A6D)).frame(width: 23, height: 4)
                        }
                }.frame(width: 54, height: 54)
            } else {
                Sprite(asset, size: 54)
            }
        }
    }

    private var isNight: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 19 || hour < 6
    }

    @ViewBuilder
    private func item(_ slot: StudioSlot, size: CGFloat) -> some View {
        if let asset = store.placed(in: slot)?.asset {
            Sprite(asset, size: size)
        }
    }

    private func deck(record: CollectedRecord?, spinning: Bool) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [Color(hex: 0x8B5A2B), Color(hex: 0x4A2E17)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 84, height: 26)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            // The platter seen from slightly above — a disc squashed into an
            // ellipse, which still spins like one.
            VinylDisc(record: record, size: 64, spinning: spinning)
                .scaleEffect(x: 1, y: 0.38)
                .frame(height: 26)
                .offset(y: -18)
            Capsule().fill(Color(hex: 0xD4D4D8))
                .frame(width: 3, height: 22)
                .rotationEffect(.degrees(spinning ? 28 : 12), anchor: .top)
                .offset(x: 32, y: -24)
                .animation(.easeInOut(duration: 0.5), value: spinning)
        }
        .frame(width: 90, height: 56)
    }

    /// A wooden crate with sleeves poking out of the top.
    private func crate(extra: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottom) {
                HStack(spacing: 2) {
                    ForEach(0..<min(4, max(1, extra)), id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill([Color(hex: 0xE11D48), Color(hex: 0x38BDF8), Color(hex: 0xFACC15), Color(hex: 0x1F2937)][i])
                            .frame(width: 8, height: 16)
                            .rotationEffect(.degrees(Double(i - 1) * 6), anchor: .bottom)
                    }
                }
                .offset(y: -12)
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xA16207))
                    .frame(width: 42, height: 22)
                    .overlay(
                        VStack(spacing: 5) {
                            Rectangle().fill(Color.black.opacity(0.25)).frame(height: 1)
                            Rectangle().fill(Color.black.opacity(0.25)).frame(height: 1)
                        }
                        .padding(.horizontal, 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.3)))
            }
            .frame(width: 42, height: 34, alignment: .bottom)
            .contentShape(Rectangle())
            if extra > 0 {
                Text("+\(extra)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .offset(x: 6, y: -4)
            }
        }
    }
}

// MARK: - Speakers

/// A speaker by the deck. The bought pair if there is one, otherwise a plain
/// wooden cabinet. The cones thump while a record spins and sit still when
/// it doesn't.
private struct Speaker: View {
    let asset: String?
    var playing: Bool
    var mirrored: Bool

    var body: some View {
        TimelineView(.animation(paused: !playing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // Two beats at different speeds, so it reads as music, not a metronome.
            let thump = playing ? CGFloat(max(0, sin(t * 9)) * 0.7 + max(0, sin(t * 4.5 + 1)) * 0.3) : 0
            Group {
                if let asset {
                    // The sprite has sound waves drawn on; they're only
                    // there while something plays.
                    Sprite(asset, size: 34)
                        .mask(alignment: .leading) { Rectangle().frame(width: playing ? 34 : 19) }
                        .scaleEffect(1 + thump * 0.08, anchor: .bottom)
                } else {
                    cabinet(thump: thump)
                }
            }
            .scaleEffect(x: mirrored ? -1 : 1)
        }
    }

    private func cabinet(thump: CGFloat) -> some View {
        VStack(spacing: 3) {
            Circle().fill(Color(hex: 0x27272A)).frame(width: 8, height: 8)
                .overlay(Circle().fill(Color(hex: 0x52525B)).frame(width: 3))
            Circle().fill(Color(hex: 0x27272A)).frame(width: 15, height: 15)
                .overlay(Circle().fill(Color(hex: 0x52525B)).frame(width: 6 + thump * 4))
                .scaleEffect(1 + thump * 0.1)
        }
        .padding(.vertical, 4).padding(.horizontal, 3)
        .background(RoundedRectangle(cornerRadius: 3).fill(
            LinearGradient(colors: [Color(hex: 0x7C4A21), Color(hex: 0x4A2E17)],
                           startPoint: .top, endPoint: .bottom)))
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }
}

// MARK: - Crate browser

/// Every record you've earned, newest first. They rise out of the crate when
/// it opens; tap one to spin it.
private struct CrateBrowser: View {
    let records: [CollectedRecord]
    @State private var lifted = false
    private var player: RecordPlayer { .shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    NowPlayingBar()
                        .animation(.spring(duration: 0.3), value: player.record?.id)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 14) {
                        ForEach(Array(records.reversed().enumerated()), id: \.element.id) { i, record in
                            tile(record)
                                .offset(y: lifted ? 0 : 260)
                                .opacity(lifted ? 1 : 0)
                                .animation(.spring(response: 0.55, dampingFraction: 0.72)
                                    .delay(Double(min(i, 16)) * 0.04), value: lifted)
                        }
                    }
                }
                .padding()
            }
            .brandBackground()
            .navigationTitle("The crate · \(records.count)")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { lifted = true }
        }
    }

    private func tile(_ record: CollectedRecord) -> some View {
        let playing = player.playingID == record.id
        let loading = player.loadingID == record.id
        return Button {
            Haptics.tap()
            player.toggle(record)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    RecordSleeve(record: record, size: 92)
                    if playing || loading {
                        Circle().fill(.black.opacity(0.55)).frame(width: 34)
                        if loading { ProgressView().tint(.white) }
                        else { Image(systemName: "stop.fill").foregroundStyle(.white) }
                    }
                }
                Text(record.title).font(.caption.bold()).lineLimit(1)
                Text(record.artist).font(.caption2).foregroundStyle(Theme.textDim).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bandmate

private struct Bandmate: View {
    let asset: String
    var size: CGFloat
    var playing: Bool

    var body: some View {
        TimelineView(.animation(paused: !playing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Sprite(asset, size: size)
                .rotationEffect(.degrees(playing ? sin(t * 6) * 6 : 0), anchor: .bottom)
                .offset(y: playing ? -abs(sin(t * 6)) * 3 : 0)
                .background(alignment: .bottom) {
                    Ellipse().fill(Color.black.opacity(0.25))
                        .frame(width: size * 0.7, height: size * 0.12)
                }
        }
    }
}

// MARK: - Notes badge

struct NotesBadge: View {
    let notes: Double
    var body: some View {
        HStack(spacing: 4) {
            Sprite("musical_note", size: 16)
            Text(IdleEngine.format(notes))
                .font(.system(.subheadline, design: .rounded).bold())
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Theme.surface2))
    }
}
