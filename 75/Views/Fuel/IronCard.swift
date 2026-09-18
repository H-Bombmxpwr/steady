import SwiftUI

/// Low iron, said out loud.
///
/// This is the one blood marker where the gap between "your labs are normal"
/// and "you feel awful and your training has stalled" is routine rather than
/// rare — ferritin can be sitting at 18 ng/mL, flagged by nobody, while every
/// session feels like wading. So when the number says low, this card leads
/// with what it means and follows with what to do at the table.
///
/// What it never does is suggest an iron supplement. Iron overload is real
/// and supplementing without a deficiency causes genuine harm, so the first
/// action in the list is always "take this to a doctor."
struct IronCard: View {
    let finding: IronCoach.Finding
    var day: DayLog
    var profile: UserProfile

    @State private var expanded = false

    private var tint: Color {
        switch finding.status {
        case .depleted: return Theme.danger
        case .low: return Theme.workoutTint
        case .watch: return Theme.alcoholTint
        case .stocked: return Theme.supplementTint
        }
    }

    private var targetMg: Double {
        IronCoach.dailyIronTargetMg(sex: profile.sex,
                                    age: profile.ageYears,
                                    isAthlete: profile.mode == .athlete)
    }

    var body: some View {
        Card(title: "Iron", icon: "drop.triangle.fill", tint: tint) {
            VStack(alignment: .leading, spacing: 10) {
                Text(finding.headline)
                    .font(.headline)
                    .foregroundStyle(tint)

                Text(finding.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let progress = IronCoach.loggedIronProgress(day: day, targetMg: targetMg) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Today's food")
                                .font(.caption)
                                .foregroundStyle(Theme.textDim)
                            Spacer()
                            Text("\(progress.eaten.formatted(.number.precision(.fractionLength(1)))) of \(progress.target.formatted(.number.precision(.fractionLength(0)))) mg")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tint)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.hairline)
                                Capsule().fill(tint)
                                    .frame(width: geo.size.width * min(1, progress.eaten / max(1, progress.target)))
                            }
                        }
                        .frame(height: 5)
                        Text("Counts only what the app knows the iron content of — plenty of logged foods don't carry one, so treat this as a floor.")
                            .font(.caption2)
                            .foregroundStyle(Theme.textDim)
                    }
                }

                if expanded {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(finding.actions.enumerated()), id: \.offset) { _, action in
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(tint).frame(width: 5, height: 5).padding(.top, 6)
                                Text(action)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if let staleness = finding.staleness {
                            Text(staleness)
                                .font(.caption)
                                .foregroundStyle(Theme.textDim)
                        }

                        Text(IronCoach.disclaimer)
                            .font(.caption2)
                            .foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { expanded.toggle() }
                } label: {
                    Label(expanded ? "Less" : "What to eat about it",
                          systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(tint)

                Text("Measured \(finding.measuredOn.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(Theme.textDim)
            }
        }
    }
}
