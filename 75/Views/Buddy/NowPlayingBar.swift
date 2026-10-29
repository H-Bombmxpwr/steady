import SwiftUI

/// The little transport under the studio while a record spins: which song,
/// how much of its preview is left, skip either way, and an × to lift the
/// needle. Hidden when nothing's on the deck.
struct NowPlayingBar: View {
    private var player: RecordPlayer { .shared }

    var body: some View {
        if let record = player.record {
            HStack(spacing: 10) {
                RecordSleeve(record: record, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    if let track = player.track {
                        Text(track.name).font(.subheadline.bold()).lineLimit(1)
                    } else {
                        Text("Finding a track…").font(.subheadline.bold()).foregroundStyle(Theme.textDim)
                    }
                    Text("\(record.artist) · \(record.title)")
                        .font(.caption).foregroundStyle(Theme.textDim).lineLimit(1)
                    if player.isPlaying {
                        HStack(spacing: 6) {
                            ProgressView(value: min(player.elapsed, player.duration), total: player.duration)
                                .tint(Theme.accent)
                            Text("-\(Self.clock(player.remaining))")
                                .font(.caption2).monospacedDigit().foregroundStyle(Theme.textDim)
                        }
                    }
                }
                Spacer(minLength: 0)
                if player.isPlaying {
                    control("backward.fill") { player.previous() }
                    control("forward.fill") { player.next() }
                }
                control("xmark") { player.stop() }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if let missing = player.unavailable {
            HStack {
                Text("No previews for \(missing.title) in Apple Music.")
                    .font(.caption).foregroundStyle(Theme.textDim)
                Spacer(minLength: 0)
                control("xmark") { player.stop() }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
        }
    }

    private func control(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
