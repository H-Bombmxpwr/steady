import SwiftUI

/// A badge you can earn: streaks, pounds down, days tracked.
struct Milestone: Identifiable {
    let id: String
    let icon: String
    let label: String
    let tint: Color
    let earned: Bool

    static func all(plan: Plan, targets: DailyTargets) -> [Milestone] {
        let streak = CalorieEngine.streakStats(plan: plan, targets: targets).current
        let lost = max(0, plan.startingWeight - CalorieEngine.trendWeight(plan: plan))
        let tracked = plan.days.filter(\.hasActivity).count

        var out: [Milestone] = []
        for days in [3, 7, 14, 30, 50, 75] {
            out.append(Milestone(id: "streak\(days)",
                                 icon: "flame.fill",
                                 label: "\(days)-day streak",
                                 tint: Color(hex: 0xF97316),
                                 earned: streak >= days))
        }
        for lb in [5, 10, 15, 20, 25] {
            out.append(Milestone(id: "lost\(lb)",
                                 icon: "arrow.down.circle.fill",
                                 label: "\(lb) lb down",
                                 tint: Theme.weightTint,
                                 earned: lost >= Double(lb)))
        }
        for days in [7, 30, 75, 100] {
            out.append(Milestone(id: "tracked\(days)",
                                 icon: "checkmark.seal.fill",
                                 label: "\(days) days tracked",
                                 tint: Theme.supplementTint,
                                 earned: tracked >= days))
        }
        return out
    }
}

/// Earned badges up front, the next locked ones as motivation.
struct MilestonesCard: View {
    let milestones: [Milestone]

    private var display: [Milestone] {
        let earned = milestones.filter(\.earned)
        let next = milestones.filter { !$0.earned }.prefix(3)
        return earned + next
    }

    var body: some View {
        Card(title: "Milestones", icon: "rosette", tint: Theme.warn) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(display) { m in
                        VStack(spacing: 5) {
                            Image(systemName: m.icon)
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(m.earned ? .white : Color.secondary)
                                .frame(width: 46, height: 46)
                                .background(
                                    Circle().fill(m.earned
                                        ? AnyShapeStyle(LinearGradient(
                                            colors: [m.tint, m.tint.opacity(0.6)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
                                        : AnyShapeStyle(Theme.surface2))
                                )
                                .overlay {
                                    if !m.earned {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.secondary)
                                            .offset(x: 16, y: 16)
                                    }
                                }
                            Text(m.label)
                                .font(.caption2)
                                .foregroundStyle(m.earned ? .primary : Theme.textDim)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            // Own horizontal drags so swiping the badges scrolls them
            // instead of flipping to the next tab in glass mode.
            .claimsHorizontalDrag()
        }
    }
}

// MARK: - Confetti

/// Lightweight one-shot confetti burst for newly earned milestones.
struct ConfettiView: View {
    @State private var fall = false

    private struct Piece: Identifiable {
        let id = UUID()
        let x: CGFloat          // 0...1 across the width
        let delay: Double
        let size: CGFloat
        let rotation: Double
        let color: Color
    }

    private let pieces: [Piece] = {
        let palette: [Color] = [Theme.accent, Theme.accent2, Theme.warn,
                                Theme.foodTint, Theme.waterTint,
                                Theme.weightTint, Theme.photoTint]
        return (0..<42).map { _ in
            Piece(x: .random(in: 0...1),
                  delay: .random(in: 0...0.5),
                  size: .random(in: 6...11),
                  rotation: .random(in: -540...540),
                  color: palette.randomElement()!)
        }
    }()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { p in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(p.color)
                        .frame(width: p.size, height: p.size * 0.6)
                        .rotationEffect(.degrees(fall ? p.rotation : 0))
                        .position(x: p.x * geo.size.width,
                                  y: fall ? geo.size.height + 30 : -30)
                        .animation(.easeIn(duration: 2.1).delay(p.delay), value: fall)
                        .opacity(fall ? 0.9 : 1)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            fall = true
        }
    }
}
